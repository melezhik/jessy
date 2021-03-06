require 'fileutils'
require 'diff/lcs'
require 'diff/lcs/htmldiff'
require 'open3'

class BuildsController < ApplicationController

    skip_before_filter :authenticate_user!, :only => [ :destroy, :download, :revert, :create ]

    def create

        @project = Project.find(params[:project_id])

        @build = @project.builds.create!
        
        FileUtils.mkdir_p @build.local_path
        @build.touch_log_file

        make_snapshot @project, @build

        if current_user.nil?
            comm = 'anonimous'
        else
            comm = current_user.username
        end

        @project.history.create!( { :commiter => comm, :action => "run build ID: #{@build.id}" })

        Delayed::Job.enqueue(BuildAsync.new(@project, @build, Distribution, Setting.take, { :root_url => root_url  } ),0, Time.zone.now ) 
        message = "build ID: #{@build.id} for project ID: #{params[:project_id]} has been successfully scheduled at #{Time.zone.now}"
        flash[:notice] = message

        if request.env["HTTP_REFERER"].nil?
            render  :text => "#{message}\n"
        else
            redirect_to @project 
        end
    
    end

    def revert

        @project = Project.find(params[:project_id])
        parent_build = Build.find(params[:id])
        parent_project =  Project.find(parent_build.project_id)


        if current_user.nil?
            comm = 'anonimous'
        else
            comm = current_user.username
        end

        @project.history.create!  :commiter => comm, :action => "revert project to build ID: #{parent_build.id}" 

        if parent_build.succeeded?

            @build = @project.builds.create!({ :parent_id => parent_build.id })

            FileUtils.mkdir_p @build.local_path
            @build.touch_log_file

            @build.log :info, "create build ID:#{@build.id}"

            # remove all project's sources 
            @project.sources.each  do |s|
                indexed_url =  s._indexed_url
                s.destroy!
                @build.log :debug, "remove #{indexed_url}"
            end

            # creates new project's sources based on snapshot for parent build
            # creates new build's shanpshot as copy of parent's build one
            i = 0
            parent_build.components.each do |cmp|
                i += 1    
                new_source = @project.sources.create({ :scm_type => cmp[:scm_type] , :url => cmp.url , :sn => i*10, :git_tag => cmp[:git_tag], :git_branch => cmp[:git_branch], :git_folder => cmp[:git_folder]  })
                new_source.save!
                @build.log :debug, "add #{cmp.indexed_url} to project ID:#{@project.id}"
                if cmp.main?
                    @project.update!({ :distribution_source_id => new_source.id })
                    @build.log :debug, "mark source ID: #{new_source.id}; indexed_url: #{cmp.indexed_url} as an main application component source for project ID: #{@project.id}"
                end
                cmp_new = @build.snapshots.create!({ 
                    :indexed_url => cmp[:indexed_url], 
                    :revision => cmp[:revision], 
                    :scm_type => cmp[:scm_type], 
                    :schema => cmp[:schema],
                    :is_distribution_url => cmp[:is_distribution_url],
                    :git_branch => cmp[:git_branch], 
                    :git_tag => cmp[:git_tag], 
                    :git_folder => cmp[:git_folder]
                })
                cmp_new.save!
            end

            # re-read project data from DB
            @project.reload

            settings = Setting.take
            copy_stack_cmd = "pinto --root=#{settings.pinto_repo_root} copy #{parent_project.id}-#{parent_build.id} #{@project.id}-#{@build.id} --no-color"

            @build.log :debug, "running command: #{copy_stack_cmd}"
            execute_command copy_stack_cmd
            @build.log :debug, "command: #{copy_stack_cmd} succeeded"

            @build.update  :has_stack => true, :state => 'succeeded', :distribution_name => parent_build[:distribution_name]
            @build.save!

            if params[:no_copy_install_base]
                @build.log :debug, "do not copy install base due to param[:no_copy_install_base] is set to <#{params[:no_copy_install_base]}>"
                flash[:notice] = "build ID: #{@build.id} for project ID: #{params[:project_id]} has been successfully reverted; parent build ID: #{@build.parent_id}"
            else
                @build.log :debug, "create jc build"
    
                resp = @project.jcc.request :post, '/builds',  'build[key_id]' => "#{@build.id}" 
                jc_id = resp.headers[:build_id]
                @build.log :debug, "create jc build ok. js_id:#{jc_id}"

                @build.update!  :jc_id => jc_id
                @build.save!
    
                @build.log :debug, "copy ancestor build via jc server, ancestor build_id: #{parent_build.id}"
                resp = @project.jcc.request :post, "/builds/#{jc_id}/copy", 'jc_id' => "#{parent_build.jc_id}"
                @build.log :debug, "copy jc build ok"
    
                @build.update!  :has_install_base => true 
                @build.save!
    
                @build.log :info,  "successfully reverted project to build ID: #{parent_build.id}; new build ID: #{@build.id}"
                message = "build ID: #{@build.id} for project ID: #{params[:project_id]} has been successfully reverted; parent build ID: #{@build.parent_id}"    
                flash[:notice] = message
            end            
        else
            message =  "cannot revert project to unsucceded build; parent build ID:#{parent_build.id}; state:#{parent_build.state}"
            flash[:alert] = message
        end

        if request.env["HTTP_REFERER"].nil?
            render  :text => "#{message}\n"
        else
            redirect_to @project
        end

    end

    def show
        @project = Project.find(params[:project_id])
        @build = Build.find(params[:id])
        @log_entries = @build.recent_log_entries
    end

    def configuration
        @project = Project.find(params[:project_id])
        @build = Build.find(params[:id])
        @data = @build.snapshots
    end

    def edit
        @project = Project.find(params[:project_id])
        @build = Build.find(params[:id])
    end

    def update 
        @project = Project.find(params[:project_id])
        @build = Build.find(params[:id])
        
        if @build.update(builds_params)
            @project.history.create!( { :commiter => current_user.username, :action => "annotate build ID: #{@build.id}" })
            flash[:notice] = "build ID:#{@build.id} has been successfully annotated"
            redirect_to @project
        else
            flash[:alert] = "error has been occured when annotating build ID:#{@build.id}"
            render 'edit'
        end
    end

    def full_log
        @project = Project.find(params[:project_id])
        @build = Build.find(params[:id])
        @log_entries = @build.all_log_entries
    end

    def list
        @project = Project.find(params[:project_id])
        @build = Build.find(params[:id])
        @list = `pinto --root=#{Setting.take.pinto_repo_root} list -s #{@project.id}-#{@build.id} --no-color --format '%a/%f' | sort | uniq `.split "\n"
    end

    def changes

        @project = Project.find(params[:project_id])
        @build = Build.find(params[:id])


        if ! params[:build].nil? and  ! params[:build][:id].nil?
            @precendent =  Build.find(params[:build][:id]) 
        else
            @precendent =  @build.precedent 
        end

        if @precendent.nil?
            flash[:alert] = "cannot find precendent for build ID:#{@build.id}"
            redirect_to project_path(@project,@build)
        else

            @pinto_diff = execute_command("pinto --root=#{Setting.take.pinto_repo_root} diff #{@project.id}-#{@build.id} #{@project.id}-#{@precendent.id}  --no-color", false)
    
            Diff::LCS::HTMLDiff.can_expand_tabs = false
    
            s = StringIO.new
            
            if  @precendent.snapshots.empty?
                @snapshot_diff = "<pre>insufficient data for build ID: #{@precendent.id}</pre>"
            elsif  @build.snapshots.empty?
                @snapshot_diff = "<pre>insufficient data for build ID: #{@build.id}</pre>"
            else
                Diff::LCS::HTMLDiff.new( 
                    @precendent.components.map  { |cmp| ( cmp.main? ? '(app) ' : '' ) +  (cmp[:indexed_url] || 'NULL') }.sort, 
                    @build.components.map       {|cmp|  ( cmp.main? ? '(app) ' : '' ) +  (cmp[:indexed_url] || 'NULL') }.sort , 
                    :title => "diff #{@build.id} #{@precendent.id}" ,
                    :output => s
                ).run
    
                @snapshot_diff = s.string
                @snapshot_diff.sub!(/<html>.*<body>/m) { "" } 
                @snapshot_diff.gsub! '<h1>', '<strong>'
                @snapshot_diff.gsub! '</h1>', '</strong>'
                @snapshot_diff.sub! '</html>', ''
                @snapshot_diff.sub! '</body>', ''
    
            end

            @history = History.order( id: :desc ).where('project_id = ? AND created_at >= ?  AND created_at <= ? ', @project[:id], @precendent[:created_at], @build[:created_at] );

        end

    end

    def destroy
        @project = Project.find(params[:project_id])
        build = Build.find(params[:id])

        if current_user.nil?
            comm = 'anonimous'
        else
            comm = current_user.username
        end


        `pinto --root=#{Setting.take.pinto_repo_root} kill #{@project.id}-#{build.id}`

        jc_id = nil
        if build.locked? or  build.released?
            message = "cannot delete locked  or released build! ID:#{params[:id]}"
            flash[:alert] = message
        else
            FileUtils.rm_rf build.local_path
            jc_id = build.jc_id
            build.destroy
            if user_signed_in?
                @project.history.create!( { :commiter => comm, :action => "delete build ID: #{params[:id]}" })
                flash[:notice] = "build ID:#{params[:id]} for project ID:#{params[:project_id]} has been successfully deleted"
            else
                @project.history.create!( { :action => "delete build ID: #{params[:id]}" })
            end


            if jc_id
                @project.history.create!( { :commiter => comm, :action => "delete jc build, build ID: #{params[:id]}, jc ID: #{jc_id}" })            
                @project.jcc.request :delete, "/builds/#{jc_id}"
            end
    
            message = "build, ID: #{params[:id]} has been successfully destroyed" 
    
        end

        if request.env["HTTP_REFERER"].nil?
            render  :text => "#{message}\n"
        else
            redirect_to @project 
        end

    end

    def release 
        @project = Project.find(params[:project_id])
        @build = Build.find(params[:id])


        if @build.update({ :released => true, :locked => true })
            flash[:notice] = "build ID:#{@build.id} has been successfully marked as released"
            @project.history.create!( { :commiter => current_user.username, :action => "release build ID: #{@build.id}" })
            redirect_to @project
        else
            flash[:alert] = "error has been occured when trying to mark this build as released ID:#{@build.id}"
            render 'edit'
        end
    end

    def lock
        @project = Project.find(params[:project_id])
        @build = @project.builds.find(params[:id])

        if @build.update({:locked => true })
            flash[:notice] = "build ID:#{params[:id]}; has been sucessfully locked"
            @project.history.create!( { :commiter => current_user.username, :action => "lock build ID: #{@build.id}" })
            redirect_to [@project]
        else
            flash[:alert] = "error has been occured when locking build ID:#{params[:id]}"
            redirect_to [@project]
        end
    end

    def unlock
        @project = Project.find(params[:project_id])
        @build = @project.builds.find(params[:id])
        if @build.update({:locked => false })
            flash[:notice] = "build ID:#{params[:id]}; has been sucessfully unlocked"
            @project.history.create!( { :commiter => current_user.username, :action => "unlock build ID: #{@build.id}" })
            redirect_to [@project]
        else
            flash[:alert] = "error has been occured when unlocking build ID:#{params[:id]}"
            redirect_to [@project]
        end
    end


    def download
         @build = Build.find(params[:id])
         @project = Project.find(params[:project_id])
         redirect_to "#{@project.jc_host}/artefacts/#{params[:archive]}"
    end


    def jc_log
         @build = Build.find(params[:id])
         @project = Project.find(params[:project_id])
         res = @project.jcc.request :get, "/builds/#{@build[:jc_id]}"
         @data = "#{res}"
    end

    def cpanm_log
         @build = Build.find(params[:id])
         @project = Project.find(params[:project_id])
         res  = @project.jcc.request :get, "/builds/#{@build[:jc_id]}/cpanm_log?cpanm_id=#{params[:cpanm_id]}"
         @data = "#{res}"
    end

private

  def builds_params
      params.require( :build ).permit( :comment )
  end

  def execute_command(cmd, raise_ex = true )
    res = []
    logger.debug "running command: #{cmd}"
    Open3.popen2e(cmd) do |stdin, stdout_err, wait_thr|
        while line = stdout_err.gets
            logger.debug line
            res << line.chomp
        end
        exit_status = wait_thr.value
        retval = exit_status.success?
        unless exit_status.success?
          logger.debug "command failed"
          raise "command #{cmd} failed" if raise_ex == true
       end
    end
        logger.debug "command succeeded"
    res

  end

   def make_snapshot project, build
         # snapshoting current configuration before schedulling new build
         project.sources_enabled.each  do |s|
            cmp = build.snapshots.create!({ :indexed_url => s._indexed_url, :scm_type => s.scm_type, :git_folder => s.git_folder, :git_branch => s.git_branch, :git_tag => s.git_tag    } )
            cmp.save!
            if project.distribution_indexed_url == s._indexed_url
                cmp.update!( { :is_distribution_url => true } )
                cmp.save!
            end
         end
   end  

end
