require 'uri'
class Source < ActiveRecord::Base

    belongs_to :project
    validates :url, presence: true

    def enabled?
        state == true
    end


    def git_br_or_tag

        if ! git_branch.nil? and ! :git_branch.empty?
            git_branch
        elsif ! git_tag.nil? and ! :git_tag.empty?
            "#{git_tag} tag"
        else
            'master'    
        end

    end

    def _indexed_url
        res = nil
        if scm_type == 'svn'
            begin
                res = URI.split(url)[2] + (URI.split(url)[5]).sub(/\/$/,"")
            rescue URI::InvalidURIError => ex
                res = url
            end
        elsif scm_type == 'git'
            res = url + ' ' + git_br_or_tag + ' ' + ( git_folder || '' )
        end
        res
    end

end
