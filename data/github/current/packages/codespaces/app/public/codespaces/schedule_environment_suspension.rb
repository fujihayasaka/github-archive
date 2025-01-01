# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class ScheduleEnvironmentSuspension
    def self.call(codespace)
      new(codespace).call
    end

    def initialize(codespace)
      @codespace = codespace
    end

    def call
      CodespacesSuspendEnvironmentJob.perform_later(codespace: codespace) if codespace_suspendable?
    end

    def codespace_suspendable?
      !environment.suspended?
    end

    private

    attr_reader :codespace

    def environment
      environment_json = client.fetch_environment!(codespace.guid)
      ::Codespaces::Environment.from_json(environment_json)
    end

    def client
      ::Codespaces::VscsClient.for_codespace(codespace)
    end
  end
end
