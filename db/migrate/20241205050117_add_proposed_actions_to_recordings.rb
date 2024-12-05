class AddProposedActionsToRecordings < ActiveRecord::Migration[7.1]
  def change
    add_column :recordings, :proposed_actions, :text
  end
end
