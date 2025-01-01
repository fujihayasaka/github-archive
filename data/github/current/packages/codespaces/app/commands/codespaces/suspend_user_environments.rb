# typed: true
# frozen_string_literal: true

module Codespaces
  class SuspendUserEnvironments < Command
    def initialize(
      user,
      scope: user.codespaces.provisioned,
      error_reporter: Codespaces::ErrorReporter
    )
      @user = user
      @scope = scope
      @error_reporter = error_reporter
    end

    def perform
      @scope.find_each do |codespace|
        @error_reporter.push(codespace: codespace) do
          Codespaces::SuspendEnvironment.call(codespace)
        end
      end
    end
  end
end
