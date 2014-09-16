cwd = File.expand_path(File.join(File.dirname(__FILE__), %w[ ../ ../ ]))
port = 3000
app = 'jessy'

Eye.config do
    logger "#{cwd}/log/eye.log"
end

Eye.application app do

  stop_on_delete true 

  working_dir cwd
  stdall "#{cwd}/log/trash.log" # stdout,err logs for processes by default

    group 'dj' do

        chain :action => :restart, :grace => 5.seconds
        chain :action => :start, :grace => 0.2.seconds
    
        workers = (ENV['dj_workers']||'2').to_i
        (1..workers).each do |i|
            process "dj#{i}" do
                pid_file "tmp/pids/delayed_job.#{i}.pid" # pid_path will be expanded with the working_dir
                start_command "./bin/delayed_job start -i #{i}"
                stop_command "./bin/delayed_job stop -i #{i}"
                daemonize false
                stdall "#{cwd}/log/dj.eye.log"
                env 'RESTCLIENT_LOG' => "#{cwd}/log/rc.log"
                env 'PINTO_REPOSITORY_ROOT' =>  ENV['HOME'] + '/.jessy/repo/'
            end
        end

    end

    process :api do
        pid_file "tmp/pids/server.pid"
        start_command "puma -C config/puma.rb -d --pidfile #{cwd}/tmp/pids/server.pid"
        daemonize false
        stdall "#{cwd}/log/api.eye.log"
        start_timeout 15.seconds
        stop_timeout 15.seconds
        env 'PINTO_HOME' => ENV['HOME'] + '/opt/local/pinto'
        env 'PINTO_REPOSITORY_ROOT' =>  ENV['HOME'] + '/.jessy/repo/'
    end

end
