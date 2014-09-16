require 'fileutils'
require 'open3'
require 'timeout'

class BuildJessy < Struct.new( :build_async, :project, :build, :distributions, :settings, :env  )

    def run

         build_async.log :debug,  "project.verbose: #{project[:verbose]}"
         build_async.log :debug,  "settings.force_mode: #{settings[:force_mode]}"
         build_async.log :debug,  "settings.pinto_repo_root: #{settings.pinto_repo_root}"
         build_async.log :debug,  "settings.skip_missing_prerequisites: #{settings.skip_missing_prerequisites || 'not set'}"
         build_async.log :debug,  "settings.jc_timeout: #{settings.jc_timeout}"
         build_async.log :debug,  "build has parent? #{build.has_parent? ? build.parent_id : 'no'}"
         build_async.log :debug,  "build has ancestor? #{build.has_ancestor? ? build.ancestor.id : 'no'}"
         build_async.log :debug,  "project.jc_host: #{project[:jc_host]}"

         _initialize
            

         raise "main application component not found for this build" unless build.has_main_component?

         jcc = JCC.new project.jc_host

         build_async.log :debug,  "main application component found: #{build.main_component[:indexed_url]}"
  
            distributions_list = []
            final_distribution_archive = nil
            main_cmp_dir = nil
            final_distribution_revision = nil
            
            build_async.log :debug, "create jc build"

            resp = jcc.request :post, '/builds',  'build[key_id]' => "#{build.id}" 
            jc_id = resp.headers[:build_id]
            build_async.log :debug, "create jc build ok. jc_id:#{jc_id}"

            build.update!({ :jc_id => jc_id })
            build.save!
         
            if build.has_ancestor?
                build_async.log :debug, "copy ancestor build via jc server, ancestor build_id: #{build.ancestor.id}"
                resp = jcc.request :post, "/builds/#{jc_id}/copy", 'key_id' => "#{build.ancestor.id}"
                build_async.log :debug, "copy jc build ok"
                build.update!({ :has_install_base => true })
                build.save!
            else
                build_async.log :warn, "build has no ancestor, hope it's okay"
                build.update!({ :has_install_base => true })
                build.save!
            end
            
            
            build.components.each  do |cmp|

                 build_async.log :info,  "processing component: #{cmp[:indexed_url]}"
    
                 FileUtils.rm_rf "#{build.local_path}/#{cmp.local_path}"
                 FileUtils.mkdir_p "#{build.local_path}/#{cmp.local_path}"
                 build_async.log :debug,  "component's local path: #{build.local_path}/#{cmp.local_path} has been successfully created"
    
                 if build.has_ancestor? and record = build.ancestor.component_by_indexed_url(cmp[:indexed_url])
                        cmp.update!({ :revision => record[:revision] })
                        cmp.save!
                        build_async.log :debug, "found revsion: #{record[:revision]} in ancestor build for component: #{cmp[:indexed_url]}"
                 end
        
                 # construct scm specific object for component 
                 scm_handler = SCM::Factory.create cmp, "#{build.local_path}/#{cmp.local_path}"

                 build_async.log :debug,  "component's scm hanlder class: #{scm_handler.class}"

                 _execute_command scm_handler.checkout_cmd

                 rev = scm_handler.last_revision

                 build_async.log :debug,  "last revision extracted from repoisitory: #{rev}"
                    
                 if (! cmp.revision.nil? and ! rev.nil?  and ! cmp.main? and cmp.revision == rev  and settings.force_mode == false )
    	 	        build_async.log :debug, "this component is already installed at revision: #{rev}, skip ( enable settings.force_mode to change this )"
	    	        next
    	         end
    
                 if (! cmp.revision.nil? and ! rev.nil? )
                    build_async.log :debug,  "changes found for #{cmp.url} between #{rev} and #{cmp.revision}"
                    _execute_command scm_handler.changes_cmd rev
                    _execute_command scm_handler.diff_cmd rev
                 end
	    
        	     pinto_distro_rev =  "#{rev}-#{build.id}"


                 build_async.log :debug, "component's source code has been successfully checked out"
                 
                 if ( ! cmp.main? and record = distributions.find_by(indexed_url: cmp.indexed_url, revision: rev) )
                     build_async.log :debug, "component's distribution is already pulled before as #{record[:distribution]}"
                     archive_name_with_revision = record[:distribution]
                     _pull_distribution_into_pinto_repo archive_name_with_revision # re-pulling distribution again, just in case 
                 else
    
                     archive_name = _create_distribution_archive cmp
                     build_async.log :debug, "component's distribution archive #{archive_name} has been successfully created"
    
                     archive_name_with_revision = _add_distribution_to_pinto_repo cmp, archive_name, pinto_distro_rev
    
                     # paranoid check:
    		         _distribution_in_pinto_repo! archive_name_with_revision
                     build_async.log :debug, "component's distribution archive #{archive_name_with_revision} has been successfully added to pinto repository"
    
                     if cmp.main?
                         final_distribution_archive = archive_name_with_revision
          		         final_distribution_revision = pinto_distro_rev
                         main_cmp_dir = archive_name.sub('.tar.gz','')
                         build_async.log :debug, "application main distribution directory : #{main_cmp_dir}"
                         build_async.log :debug, "application main distribution archive : #{final_distribution_archive}"
                         build_async.log :debug, "application main distribution revision : #{final_distribution_revision}"
                     else
                         new_distribution = distributions.new
                         new_distribution.update({ :revision => rev, :url => cmp.url, :distribution => archive_name_with_revision,  :indexed_url => cmp.indexed_url })
                         new_distribution.save
                     end
    
                 end
    
                 distributions_list << { :archive_name_with_revision => archive_name_with_revision, :revision => rev, :cmp => cmp }
    
    
        end

        build_async.log :debug, "schedulle targets install into jc service, please wait for a while, take some tea or coffee ..."
        dlist = distributions_list.map { |i| "t[]=PINTO/#{i[:archive_name_with_revision]}"  }.join '&'
        resp = jcc.request :post, "/builds/#{jc_id}/install?#{dlist}", 'cpan_mirror' => "#{env[:root_url]}/repo/stacks/#{project.id}-#{build.id}"

        processed_cnt = 0; failed_cnt = 0; ts = settings.jc_timeout; seen = Hash.new

        begin
            status = Timeout::timeout(ts) {
                while processed_cnt != distributions_list.size
                    distributions_list.reject{|i| seen.has_key? i[:archive_name_with_revision] }.each do |i|
                         #resp = jcc.request :get, "/builds/#{jc_id}/short_log"
                         #build_async.log :debug, "#{resp}" 
                         resp = jcc.request :get, "/builds/#{jc_id}/target_state?name=PINTO/#{i[:archive_name_with_revision]}"
                         if resp.headers[:target_state] == 'ok'
                            processed_cnt += 1
                            build_async.log :debug, "#{i[:archive_name_with_revision]} ... #{resp.headers[:target_state]}"
                            seen[i[:archive_name_with_revision]] = 1
                            i[:cmp].update!({ :revision => i[:revision] })    
                            i[:cmp].save!
                         elsif resp.headers[:target_state] == 'failed'
                            build_async.log :debug, "#{i[:archive_name_with_revision]} ... #{resp.headers[:target_state]}"
                            seen[i[:archive_name_with_revision]] = 1
                            processed_cnt += 1
                            failed_cnt += 1
                         end
                    end
                end
            }
        rescue Timeout::Error => e
            resp = jcc.request :get, "/builds/#{jc_id}/summary"
            raise "timeout exceeded (#{ts} seconds) while waiting response from jc server. build summary: #{resp}"
        end


        resp = jcc.request :get, "/builds/#{jc_id}/summary"
        build_async.log :debug, "js build summary: #{resp}"


        if failed_cnt > 0
            raise "#{failed_cnt} targets failed to install"
        end
    
        if final_distribution_archive.nil?
            raise "main component's distribution archive not found!" 
        end


        url_p = "#{env[:root_url]}/repo/stacks/#{project.id}-#{build.id}/authors/id/P/PI/PINTO/#{final_distribution_archive}"
        resp = jcc.request :post, "/builds/#{jc_id}/artefact", 'url' => url_p, 'orig_dir' => main_cmp_dir

        dist_name = resp.headers[:dist_name]
        build.update({ :distribution_name => dist_name })
        build.save

        build_async.log :debug, "artefact successfully created: #{dist_name}"
        build_async.log :info,  "done building"

    end

    def _execute_command(cmd, raise_ex = true)
    
            build_async.log :info, "running command: #{cmd}"
    
            exit_status = nil

            Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
    
                while line = stdout.gets("\n")
                    build_async.log :debug,  line
                end
    
                while line = stderr.gets("\n")
                    build_async.log :error,  line
                end
    
                exit_status = wait_thr.value
    
    
                if exit_status.success?
                    build_async.log :debug, "command successfully executed, exit status: #{exit_status}"
                else
                    build_async.log :error, "command unsuccessfully executed, exit status: #{exit_status}"
                    raise "command unsuccessfully executed, exit status: #{exit_status}" if raise_ex == true
                end
            end

            exit_status.success?

        end
    
    def _create_distribution_archive cmp
        cmd = []
        cmd <<  "cd #{build.local_path}/#{cmp.local_path}"
        cmd <<  "rm -rf *.gz && rm -rf MANIFEST"
        cmd <<  _set_perl5lib("#{ENV['HOME']}/lib/perl5")

        if File.exists? "#{build.local_path}/#{cmp.local_path}/Build.PL"

            if project[:verbose] == true
    	        cmd <<  "perl Build.PL --quiet 1>/dev/null"
            else
    	        cmd <<  "perl Build.PL --quiet 1>/dev/null 2>&1"
            end

            if project[:verbose] == true
                cmd <<  "./Build realclean && perl Build.PL --quiet 1>/dev/null"
            else
                cmd <<  "./Build realclean && perl Build.PL --quiet 1>/dev/null 2>&1"
            end

            cmd <<  "./Build manifest --quiet 1>/dev/null"
            cmd <<  "./Build dist --quiet 1>/dev/null"
        else
	        cmd <<  "perl Makefile.PL 1>/dev/null"
            cmd <<  "make realclean && perl Makefile.PL 1>/dev/null"
            cmd <<  "make manifest 1>/dev/null"
            cmd <<  "make dist 1>/dev/null"
        end
        _execute_command(cmd.join(' && '))
        distro_name = `cd #{build.local_path}/#{cmp.local_path} && ls *.gz`.chomp!
    end

    def _distribution_in_pinto_repo! archive_name_with_revision
        cmd =  "export PINTO_LOCKFILE_TIMEOUT=10000 && pinto -r #{settings.pinto_repo_root} list -s #{_stack} -D #{archive_name_with_revision} --no-color"
        _execute_command(cmd)
    end

    def _pull_distribution_into_pinto_repo archive_name_with_revision
        cmd =  "export PINTO_LOCKFILE_TIMEOUT=10000 && pinto -r #{settings.pinto_repo_root} pull -s #{_stack} PINTO/#{archive_name_with_revision} #{settings.skip_missing_prerequisites_as_pinto_param} --no-color"
        _execute_command(cmd)
    end

    def _add_distribution_to_pinto_repo cmp, archive_name, rev
        archive_name_with_revision = archive_name.sub('.tar.gz', ".#{rev}.tar.gz")
        cmd = []
        cmd <<  "cd #{build.local_path}/#{cmp.local_path}"
        cmd << "mv #{archive_name} #{archive_name_with_revision}"
        cmd <<  "export PINTO_LOCKFILE_TIMEOUT=10000 &&  pinto -r #{settings.pinto_repo_root} add -s #{_stack} #{settings.skip_missing_prerequisites_as_pinto_param} --author PINTO -v --use-default-message --no-color --recurse #{archive_name_with_revision}"
        _execute_command(cmd.join(' && '))
        archive_name_with_revision
    end


    def _initialize

         FileUtils.mkdir_p "#{build.local_path}/artefacts"

         build_async.log :info,  "build's local path has been successfully created: #{build.local_path}"

         if build.has_ancestor?
             build_async.log :info, "using ancestor's stack for this build - #{_ancestor_stack}"
            _execute_command "export PINTO_LOCKFILE_TIMEOUT=10000 && pinto --root=#{settings.pinto_repo_root} copy #{_ancestor_stack} #{_stack} --no-color"
         else   
            if File.exist? "#{settings.pinto_repo_root}/stacks/#{project.id}"
                build_async.log :info, "using predefined stack for this build - #{project.id}"
                _execute_command "export PINTO_LOCKFILE_TIMEOUT=10000 && pinto --root=#{settings.pinto_repo_root} copy #{project.id} #{_stack} --no-color"
            else
                build_async.log :info, "neither ancestor's nor predefined stacks available for this build, creating very first one -  #{_stack}"
                _execute_command "export PINTO_LOCKFILE_TIMEOUT=10000 && pinto --root=#{settings.pinto_repo_root} new #{_stack} --no-color"
            end
         end

         build.update({ :has_stack => true })
         build.save!
         sleep 5 # wait for awhile, because `pinto copy` command does not create stack immediately
    end

    def _ancestor_stack
        ancestor = build.ancestor
	    "#{project.id}-#{ancestor.id}"
    end

    def _stack
	    "#{project.id}-#{build.id}"
    end
		
    def _set_perl5lib path = nil

        inc = []
        inc << path unless path.nil?

        if ! (settings.perl5lib.nil?) and ! (settings.perl5lib.empty?)
            settings.perl5lib.split(/\s+/).each do |p|
                inc << p
            end
        end
        "export PERL5LIB=#{inc.join(':')}"
    end

end


