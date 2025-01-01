# typed: true
# frozen_string_literal: true

module CodeScanning
  # AutoCodeqlConfig contains the Default Setup configuration for the repo.
  class AutoCodeqlConfig
    extend T::Sig

    attr_accessor :languages, :state, :query_suite, :threat_model, :updated_at, :schedule, :initial_languages, :creation_trigger

    def initialize(state:, languages:, query_suite:, threat_model:, updated_at:, schedule:, initial_languages:, creation_trigger:)
      @state = state
      @languages = languages
      @query_suite = query_suite
      @threat_model = threat_model
      @updated_at = updated_at
      @schedule = schedule
      @initial_languages = initial_languages
      @creation_trigger = creation_trigger
    end
  end
end
