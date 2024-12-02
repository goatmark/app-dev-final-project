class CreateRecordings < ActiveRecord::Migration[7.1]
  def change
    create_table :recordings do |t|
      t.string :recording_type
      t.text :body
      t.text :summary
      t.integer :activities_count

      t.timestamps
    end
  end
end
