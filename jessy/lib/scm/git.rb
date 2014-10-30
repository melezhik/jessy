class SCM::Git < Struct.new( :component, :path )

    def last_revision
        cmd = "cd #{path}/git-repo/ && git log -1 --pretty=format:'%h' 2>&1"
        unless component[:git_folder].nil?
            cmd << " #{component[:git_folder]}"
        end
        `#{cmd}`.chomp
    end

    def changes_cmd revision
        cmd = "cd #{path}/git-repo/ && git log --abbrev-commit #{component.revision}..#{revision}"
        unless component[:git_folder].nil?
            cmd << " -- #{component[:git_folder]}"
        end
        cmd
    end

    def diff_cmd revision
        cmd = "cd #{path}/git-repo/ && git diff #{component.revision} #{revision}"
        unless component[:git_folder].nil?
            cmd << " -- #{component[:git_folder]}"
        end
        cmd
    end

    def checkout_cmd

        cmd = \
        if ! component[:git_branch].nil? and ! component[:git_branch].empty?
            "git clone -b #{component[:git_branch] || 'master'} #{component.url} #{path}/git-repo/"
        elsif ! component[:git_tag].nil? and ! component[:git_tag].empty?
            "cur_dir=`pwd` && git clone #{component.url} #{path}/git-repo/ && cd #{path}/git-repo/ && git checkout tags/#{component[:git_tag]} && git checkout #{component[:git_tag]} && cd $cur_dir"
        else
            "git clone #{component.url} #{path}/git-repo/"
        end

        if component[:git_folder].nil?
            cmd << " && cp -r #{path}/git-repo/*  #{path}/ "
        else
            cmd << " && cp -r #{path}/git-repo/#{component[:git_folder]}/*  #{path}/ "
        end
    end

end

