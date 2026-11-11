# typed: true
# frozen_string_literal: true

module CodeScanning
  # AutoCodeqlConfig contains the Default Setup configuration for the repo.
  class AutoCodeqlConfig
    attr_accessor :languages, :state, :query_suite, :threat_model, :updated_at, :schedule, :initial_languages, :creation_trigger, :runner_label, :code_quality_enabled

    def initialize(state:, languages:, query_suite:, threat_model:, updated_at:, schedule:, initial_languages:, creation_trigger:, runner_label:, code_quality_enabled:)
      @state = state
      @languages = languages
      @query_suite = query_suite
      @threat_model = threat_model
      @updated_at = updated_at
      @schedule = schedule
      @initial_languages = initial_languages
      @creation_trigger = creation_trigger
      @runner_label = runner_label
      @code_quality_enabled = code_quality_enabled
    end

    def with_options(options)
      options = options.with_indifferent_access
      @state = options["state"] unless options["state"].nil?
      @languages = options["languages"] unless options["languages"].nil?
      @query_suite = options["query_suite"] unless options["query_suite"].nil?
      @threat_model = options["threat_model"] unless options["threat_model"].nil?
      @updated_at = options["updated_at"] unless options["updated_at"].nil?
      @schedule = options["schedule"] unless options["schedule"].nil?
      @initial_languages = options["initial_languages"] unless options["initial_languages"].nil?
      @creation_trigger = options["creation_trigger"] unless options["creation_trigger"].nil?
      @code_quality_enabled = options["code_quality_enabled"] unless options["code_quality_enabled"].nil?
      # This is an edge case
      @runner_label = options["runner_label"] if options["runner_type"].present? && options["runner_type"] == "labeled"
      self
    end

    def self.from_hash(options)
      options = options.with_indifferent_access
      new(
        state: options["state"],
        languages: options["languages"],
        query_suite: options["query_suite"],
        threat_model: options["threat_model"],
        updated_at: options["updated_at"],
        schedule: options["schedule"],
        initial_languages: options["initial_languages"],
        creation_trigger: options["creation_trigger"],
        runner_label: options["runner_label"],
        code_quality_enabled: options["code_quality_enabled"]
      )
    end

    def runner_type
      type = @runner_label.present? ? "labeled" : "standard"
    end
  end
end
