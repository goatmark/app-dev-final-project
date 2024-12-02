class Activity < ApplicationRecord
  belongs_to :recording, required: true, class_name: "Recording", foreign_key: "recording_id", counter_cache: true
  validates :action, inclusion: { in: [ "created", "updated" ] }
end
