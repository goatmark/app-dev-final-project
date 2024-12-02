class AddPayloadToActivities < ActiveRecord::Migration[7.1]
  def change
    add_column :activities, :status, :string
  end
end
