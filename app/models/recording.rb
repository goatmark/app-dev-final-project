class Recording < ApplicationRecord
  has_many  :activities, class_name: "Activity", foreign_key: "recording_id", dependent: :destroy
  validates :recording_type, inclusion: { in: [ "note", "task", "ingredient", "recipe", "recommendation", "idea" ] }
end
