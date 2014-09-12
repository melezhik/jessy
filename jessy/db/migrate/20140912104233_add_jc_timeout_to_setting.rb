class AddJcTimeoutToSetting < ActiveRecord::Migration
  def change
    add_column :settings, :jc_timeout, :integer, :default => 3600
  end
end
