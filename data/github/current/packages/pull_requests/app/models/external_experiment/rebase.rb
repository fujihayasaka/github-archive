# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module ExternalExperiment
  class Rebase
    def self.call(payload, repo_id:)
      new(payload, repo_id: repo_id).call
    end

    def initialize(payload, repo_id:)
      @payload = payload.deep_symbolize_keys
      @repo_id = repo_id
    end

    attr_reader :payload, :repo_id

    # Parse the payload, publish experiment data, and return the control arm value.
    def call
      parsed = GitHub::Experiment::External.parse!(payload)
      inject_context(parsed.payload)
      parsed.publish!
    rescue GitHub::Experiment::External::InvalidPayload => e
      Failbot.report(e)
    end

    private

    # Add data to the payload context to aid with mismatch debugging.
    def inject_context(payload)
      payload[:context] ||= {}
      payload[:context][:repo_id] = repo_id
    end
  end
end
