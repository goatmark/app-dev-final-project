class CreateActivities < ActiveRecord::Migration[7.1]
  def change
    create_table :activities do |t|
      t.string :action_type
      t.integer :recording_id
      t.string :page_id
      t.string :database_id
      t.string :action
      t.string :page_url

      t.timestamps
    end
  end
end
