# typed: true
# frozen_string_literal: true

module Licensing
  class FeedbackLinkComponent < ApplicationComponent
    include ApplicationComponent::Rescuable

    rescue_from StandardError, with: :nothing

    FEEDBACK_SCHEDULING_URL = "https://survey3.medallia.com/?VmkLAM-ent-licensing"

    renders_one :description, -> (tag: :span, **system_arguments) do
      system_arguments[:tag] = tag
      Primer::BaseComponent.new(**system_arguments)
    end

    attr_reader :business_slug, :survey_id, :system_arguments

    def initialize(business_slug:, survey_id:, **system_arguments)
      @business_slug = business_slug
      @survey_id = survey_id
      @system_arguments = system_arguments
    end

    def render?
      !dismissed?
    end

    def dismissed?(business: business_slug)
      dismissal_setting_key = self.class.dismissal_setting_key(survey_id: survey_id, business_slug: business_slug)
      Billing::Kv.store.exists(dismissal_setting_key).value!
    end

    def self.dismissal_setting_key(survey_id:, business_slug:)
      "business.enterprise-licensing-survey.#{survey_id}.#{business_slug}.dismissed"
    end
  end
end
