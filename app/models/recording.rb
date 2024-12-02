# == Schema Information
#
# Table name: recordings
#
#  id               :bigint           not null, primary key
#  activities_count :integer
#  body             :text
#  recording_type   :string
#  status           :string
#  summary          :text
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
class Recording < ApplicationRecord
  has_many  :activities, class_name: "Activity", foreign_key: "recording_id", dependent: :destroy
  #validates :status, inclusion: { in: [ "processing", "failed", "completed" ] }
  #validates :recording_type, inclusion: { in: [ "note", "task", "ingredient", "recipe", "recommendation", "idea" ] }
end
