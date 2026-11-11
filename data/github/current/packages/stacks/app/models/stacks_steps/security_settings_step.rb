# typed: true
# frozen_string_literal: true

module StacksSteps
  class SecuritySettingsStep < Step
    def self.validate_inputs(inputs_hash, repo:, actor:, stack_repo: nil)
      if inputs_hash.fetch("vulnerability-alerts") && GitHub.enterprise?
        raise Errors::SecurityParameterError.new("Vulnerability Alerts", "Unavailable in GitHub enterprise.")
      end

      if inputs_hash.fetch("automated-security-fixes") && !GitHub.dependabot_enabled?
        raise Errors::SecurityParameterError.new("Automated Security Fixes", "Dependabot needs to be enabled.")
      end

      # vulnerability-alerts needs to be enabled before enabling automated-security-fixes
      if inputs_hash.fetch("automated-security-fixes") && !inputs_hash.fetch("vulnerability-alerts")
        raise Errors::SecurityParameterError.new("Automated Security Fixes", "Vulnerability Alerts needs to be true.")
      end
    end

    def self.get_step_name
      "SecuritySettingsStep"
    end

    def get_step_group
      StepGroup.repo_config
    end

    def run(repo:, actor:)
      method_name = "#{self.class.name}##{__method__}"
      inputs_hash = self.inputs

      if inputs_hash.fetch("vulnerability-alerts")
        repo.force_enable_vulnerability_alerts(actor: actor)

        unless repo.vulnerability_alerts_enabled?
          self.class.log_error(method_name, "Failed to enable vulnerability alerts", repo.id)
          raise Errors::SecuritySettingsError.new("Vulnerability Alerts")
        end
      end

      if inputs_hash.fetch("automated-security-fixes")
        repo.enable_vulnerability_updates(actor: actor)

        unless repo.vulnerability_updates_enabled?
          self.class.log_error(method_name, "Failed to enable automated security fixes", repo.id)
          raise Errors::SecuritySettingsError.new("Automated Security Fixes")
        end
      end
    end

    # Disables both alerts and updates for a repo
    def cleanup(repo:, actor:)
      repo.disable_vulnerability_alerts(actor: actor)
      repo.disable_vulnerability_updates(actor: actor)
    end

    def self.log_error(method, error_msg, repo_id)
      GitHub::Logger.error(fn: method,
        message: error_msg,
        repo_id: repo_id)
    end
  end
end
