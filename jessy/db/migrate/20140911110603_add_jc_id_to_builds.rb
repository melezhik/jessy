class AddJcIdToBuilds < ActiveRecord::Migration
  def change
    add_column :builds, :jc_id, :integer
  end
end
