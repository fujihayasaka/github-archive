# typed: true
# frozen_string_literal: true

class SurveyGroup < ApplicationRecord::Domain::Surveys
  belongs_to :survey
  validates_presence_of :survey

  include ::Users::BelongsToUser
  belongs_to_user_via_domain
  destroy_in_background_with :user
  validates_presence_of :user

  has_many :answers, class_name: "SurveyAnswer"
end
