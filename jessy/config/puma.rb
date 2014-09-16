workers Integer(ENV['PUMA_WORKERS'] || 6)
threads Integer(ENV['MIN_THREADS']  || 1), Integer(ENV['MAX_THREADS'] || 16)

preload_app!

rackup      DefaultRackup
environment ENV['RACK_ENV'] || 'development'

if ( ! ( ENV['RAILS_ENV'].nil? ) and  ENV['RAILS_ENV'] == 'production' )
    port 3000 
else
    port 3001
end

on_worker_boot do
  # worker specific setup
  ActiveSupport.on_load(:active_record) do
    config = ActiveRecord::Base.configurations[Rails.env] || Rails.application.config.database_configuration[Rails.env]
    config['pool'] = ENV['MAX_THREADS'] || 16
    ActiveRecord::Base.establish_connection(config)
  end
end

