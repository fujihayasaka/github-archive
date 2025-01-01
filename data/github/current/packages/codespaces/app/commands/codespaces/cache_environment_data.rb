# typed: true
# frozen_string_literal: true

module Codespaces
  class CacheEnvironmentData < Command
    def initialize(environment_data)
      @environment_data = environment_data
    end

    def perform
      return if @environment_data["id"].blank?

      codespace = Codespace.find_by(guid: @environment_data["id"])
      if @environment_data["state"].blank?
        Codespaces::ErrorReporter.report(NullStateCodespaceError.new, codespace: codespace)
        GitHub.dogstats.increment("codespaces.cache_environment_data.null_state_codespace_error")
        return
      end

      if codespace
        ActiveRecord::Base.connected_to(role: :writing) do
          codespace.update(environment_data: @environment_data)
        end
      end
    end
  end
end
