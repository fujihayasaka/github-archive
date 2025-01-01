# typed: true
# frozen_string_literal: true

module Settings
  class SecurityAnalysisDependabotUpdatesComponent < ApplicationComponent

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
      !security_configs_enabled_for_org? ||
        show_grouped_security_updates? ||
        show_dependabot_on_actions? ||
        show_dependabot_self_hosted? ||
        show_dependabot_autofix?
    end

    # Provides link to manage repo-level security settings
    def security_analysis_settings_path(repository)
      repo_settings_path = edit_repository_path(repository)
      "#{repo_settings_path}/security_analysis"
    end

    memoize def security_configs_enabled_for_org?
      @owner.security_configurations_enabled?
    end

    private

    memoize def show_grouped_security_updates?
      !@owner.is_a?(Business)
    end

    memoize def show_dependabot_on_actions?
      actions_enabled = true
      if @owner.respond_to?(:actions_disabled)
        actions_enabled = !@owner.actions_disabled?
      end
      !@owner.is_a?(Business) && actions_enabled && Dependabot.dependabot_on_actions_available_for?(@owner)
    end

    memoize def show_dependabot_self_hosted?
      self_hosted_enabled = true
      if @owner.respond_to?(:repo_self_hosted_runners_disabled_by_owner)
        self_hosted_enabled = !@owner.repo_self_hosted_runners_disabled_by_owner?
      end
      !@owner.is_a?(Business) && show_dependabot_on_actions? && self_hosted_enabled && Dependabot.dependabot_self_hosted_available_for?(@owner)
    end

    memoize def show_dependabot_autofix?
      actions_enabled = true
      if @owner.respond_to?(:actions_disabled)
        actions_enabled = !@owner.actions_disabled?
      end
      !@owner.is_a?(Business) && show_dependabot_on_actions? && actions_enabled && Dependabot.dependabot_autofix_available_for?(@owner)
    end
  end
end
