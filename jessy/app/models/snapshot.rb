class Snapshot < ActiveRecord::Base

    belongs_to :build

    validates :indexed_url, presence: true

    def local_path
        "sources/#{id}"
    end

    def url
        if scm_type == 'svn'
            r = schema + '://' +  ( indexed_url  || 'NULL' )
        elsif scm_type == 'git'
            r = indexed_url.split(" ").first
        end
        r
    end

    def main?
        is_distribution_url == true        
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

end
