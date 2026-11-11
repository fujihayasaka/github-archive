# typed: true
# frozen_string_literal: true

module DependabotSettings
  class GroupedSecurityUpdatesComponent < ApplicationComponent
    include GitHub::Memoizer
    include SecurityAnalysisSettingsHelper

    attr_reader :owner, :repo_count, :public_repo_count, :private_repo_count

    def initialize(owner:, public_repo_count: 0, repo_count: 0)
      @owner = owner
      @public_repo_count = public_repo_count
      @repo_count = repo_count
      @private_repo_count = repo_count - public_repo_count
    end

    def render?
      # Parent component already checks: GitHub.dependabot_enabled? && !@owner.is_a?(Business)
      true
    end

    def current_vulnerability_updates_grouping_enabled
      @owner.vulnerability_updates_grouping_enabled_for_new_repos?
    end

    private

    memoize def security_configs_enabled_for_org?
      @owner.security_configurations_enabled?
    end
  end
end
