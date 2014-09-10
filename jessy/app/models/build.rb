require 'fileutils'
class Build < ActiveRecord::Base

    belongs_to :project

    has_many :snapshots, :dependent => :destroy

#    validates :comment, presence: true , length: { minimum: 10 }

    def log_path
        "#{project.local_path}/#{local_path}/log.txt"
    end

    def touch_log_file
        FileUtils.touch log_path
    end

    def logger
        if @logger 
            @logger
        else
            f = File.open(log_path, 'a')
            f.sync = true
            @logger =  Logger.new f
        end
    end

    def log level, line
        logger.send( level, line.chomp )
    end


    def local_path
        "builds/#{id}"
    end

    def components 
       snapshots.order( id: :asc )
    end

    def main_component  
       snapshots.where(' is_distribution_url = ? ', true ).first
    end

    def component_by_indexed_url indexed_url
       snapshots.where(' indexed_url = ? ', indexed_url ).first
    end

    def has_main_component?
        ! main_component.nil?
    end

    def has_components?
        ! snapshots.empty?
    end

    def has_logs?
        File.readlines(log_path).size > 0
    end


    def recent_log_entries
         a = File.readlines(log_path)
         s = a.size
         if s >= recent_log_entries_number
            a[recent_log_entries_number .. -1]
         else
            a.reverse
         end   
    end

    def all_log_entries
        File.readlines(log_path)
    end

    def recent_log_entries_number
        70
    end

    def short_comment
        "#{comment[0..70]} ... "
    end

    def ancestor
         Build.limit(1).order( id: :desc ).where(' project_id = ? AND id < ? AND has_stack = ?  AND has_install_base = ? ', project_id, id, true, true ).first
    end

    def precedent
         Build.limit(1).order( id: :desc ).where(' project_id = ? AND id < ? ', project_id, id ).first
    end

    def has_parent?
        parent_id.nil? == false
    end

    def has_ancestor?
        ancestor.nil? == false
    end

    def locked?
        locked == true
    end

    def stackable?
        has_stack == true
    end

    def released?
        released == true
    end

    def succeeded?
        state == 'succeeded'
    end

    def has_install_base?
        has_install_base
    end

end

