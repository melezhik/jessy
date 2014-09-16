class RemoveForceModeFromSettings < ActiveRecord::Migration
  def change
    remove_column :settings, :force_mode, :boolean
  end
end
