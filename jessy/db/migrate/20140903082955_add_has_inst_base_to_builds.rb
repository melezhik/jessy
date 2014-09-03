class AddHasInstBaseToBuilds < ActiveRecord::Migration
  def change
    add_column :builds, :has_install_base, :boolean
  end
end
