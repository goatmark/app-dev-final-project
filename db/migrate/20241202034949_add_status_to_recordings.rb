class AddStatusToRecordings < ActiveRecord::Migration[7.1]
  def change
    add_column :recordings, :status, :string
  end
end
