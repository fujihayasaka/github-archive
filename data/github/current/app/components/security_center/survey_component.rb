# typed: true
# frozen_string_literal: true

module SecurityCenter
  class SurveyComponent < ApplicationComponent
    include ApplicationComponent::Rescuable

    rescue_from StandardError, with: :nothing

    FEEDBACK_SCHEDULING_URL = "https://aka.ms/security-overview-feedback-scheduling"

    renders_one :heading, -> (tag: :h4, **system_arguments) do
      system_arguments[:tag] = tag
      Primer::BaseComponent.new(**system_arguments)
    end

    renders_one :description, -> (tag: :span, **system_arguments) do
      system_arguments[:tag] = tag
      Primer::BaseComponent.new(**system_arguments)
    end

    attr_reader :survey_id, :system_arguments

    def initialize(survey_id:, **system_arguments)
      @survey_id = survey_id
      @system_arguments = system_arguments
    end

    def render?
      return false unless heading.present?
      !dismissed?
    end

    def dismissed?(user: current_user)
      dismissal_setting_key = self.class.dismissal_setting_key(survey_id: survey_id, user_id: user.id)
      SecurityCenter::KV.store.exists(dismissal_setting_key).value!
    end

    def self.dismissal_setting_key(survey_id:, user_id:)
      "user.security-center-survey.#{survey_id}.#{user_id}.dismissed"
    end
  end
end
