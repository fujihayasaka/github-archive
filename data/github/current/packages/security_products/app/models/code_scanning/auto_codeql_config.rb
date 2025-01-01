# typed: true
# frozen_string_literal: true

module CodeScanning
  # AutoCodeqlConfig contains the Default Setup configuration for the repo.
  class AutoCodeqlConfig
    attr_accessor :languages, :state, :query_suite, :threat_model, :updated_at, :schedule, :initial_languages, :creation_trigger, :runner_label

    def initialize(state:, languages:, query_suite:, threat_model:, updated_at:, schedule:, initial_languages:, creation_trigger:, runner_label:)
      @state = state
      @languages = languages
      @query_suite = query_suite
      @threat_model = threat_model
      @updated_at = updated_at
      @schedule = schedule
      @initial_languages = initial_languages
      @creation_trigger = creation_trigger
      @runner_label = runner_label
    end

    def runner_type
      type = @runner_label.present? ? "labeled" : "standard"
    end
  end
end
