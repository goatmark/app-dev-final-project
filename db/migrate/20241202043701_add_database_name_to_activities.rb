class AddDatabaseNameToActivities < ActiveRecord::Migration[7.1]
  def change
    add_column :activities, :database_name, :string
  end
end
