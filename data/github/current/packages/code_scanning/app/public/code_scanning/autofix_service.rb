# typed: strict
# frozen_string_literal: true

# CodeScanning::AutofixService exposes methods related to code scanning Autofix for a repository.
# Adding them here avoids having to bloat the Repository model with these methods,
# which is something the Repos team is trying to avoid: https://github.com/github/domain-isolation/discussions/241
module CodeScanning
  class AutofixService
    sig { params(repo: Repository).returns(T::Boolean) }
    def self.agentic_autofix_validation_checks_enabled?(repo)
      # Check self (repository)
      return true if repo.feature_flag_enabled?(:code_scanning_agentic_autofix_validation_checks, default: false)

      # Check owner (organization)
      return true if repo.owner&.feature_flag_enabled?(:code_scanning_agentic_autofix_validation_checks, default: false)

      false
    end

    sig { params(repo: Repository).returns(T::Boolean) }
    def self.agentic_autofix_padawan_integration_enabled?(repo)
      # Check self (repository)
      return true if repo.feature_flag_enabled?(:code_scanning_agentic_autofix_padawan_integration, default: false)

      # Check owner (organization)
      return true if repo.owner&.feature_flag_enabled?(:code_scanning_agentic_autofix_padawan_integration, default: false)

      false
    end

    sig { params(repo: Repository).returns(T::Boolean) }
    def self.iterative_autofix_regenerate_button_enabled?(repo)
      # Check self (repository)
      return true if repo.feature_flag_enabled?(:code_scanning_autofix_regenerate_button, default: false)

      # Check owner (organization)
      return true if repo.owner&.feature_flag_enabled?(:code_scanning_autofix_regenerate_button, default: false)

      false
    end
  end
end
