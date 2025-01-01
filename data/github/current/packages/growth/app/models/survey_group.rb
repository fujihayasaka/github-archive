# typed: true
# frozen_string_literal: true

class SurveyGroup < ApplicationRecord::Domain::Surveys
  belongs_to :survey
  validates_presence_of :survey

  belongs_to :user
  validates_presence_of :user

  has_many :answers, class_name: "SurveyAnswer"
end
