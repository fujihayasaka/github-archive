# typed: true
# frozen_string_literal: true

module Settings
  class SecurityAnalysisDependabotUpdatesOrgComponent < ApplicationComponent
    include GitHub::Memoizer
    include SecurityAnalysisSettingsHelper

    attr_reader :owner, :private_repo_count, :public_repo_count, :repo_count

    def initialize(owner:, public_repo_count:, repo_count:)
      @owner = owner
      @public_repo_count = public_repo_count
      @repo_count = repo_count
      @private_repo_count = repo_count - public_repo_count
    end

    def render?
      true
    end

    def show_runner_settings?
      # Conditions matching legacy self-hosted checkbox
      # Parent already checked: @owner.organization?, feature flag
      self_hosted_enabled = true
      if @owner.respond_to?(:repo_self_hosted_runners_disabled_by_owner)
        self_hosted_enabled = !@owner.repo_self_hosted_runners_disabled_by_owner?
      end

      GitHub.dependabot_enabled? &&
        !GitHub.single_tenant_enterprise? &&
        show_dependabot_on_actions? &&
        self_hosted_enabled
    end

    memoize def show_dependabot_on_actions?
      actions_enabled = true
      if @owner.respond_to?(:actions_disabled)
        actions_enabled = !@owner.actions_disabled?
      end
      actions_enabled
    end

    memoize def show_grouped_security_updates?
      # Conditions matching legacy grouped security checkbox
      # Parent already checked: @owner.organization?, feature flag
      GitHub.dependabot_enabled? && !@owner.is_a?(Business)
    end

    def dependabot_rules_enabled?
      @owner.organization? && GitHub.dependabot_rules_enabled?
    end
  end
end
