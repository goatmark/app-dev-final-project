# == Schema Information
#
# Table name: activities
#
#  id           :bigint           not null, primary key
#  action       :string
#  action_type  :string
#  page_url     :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  database_id  :string
#  page_id      :string
#  recording_id :integer
#
class Activity < ApplicationRecord
  belongs_to :recording, required: true, class_name: "Recording", foreign_key: "recording_id", counter_cache: true
  #validates :action, inclusion: { in: [ "created", "updated" ] }
end
