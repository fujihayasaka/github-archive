# typed: true
# frozen_string_literal: true

module Pages
  class LegacyBuildAnnouncementComponent < ApplicationComponent

    SHUTDOWN_DEADLINE = Time.utc(2024, 6, 30).freeze

    def initialize(repository:)
      @repository = repository
    end

    def repository
      @repository
    end

    memoize def page
      @repository.page
    end

    memoize def disabled_reason
      repository.page.dynamic_workflow_disabled_reason
    end

    def use_only_self_hosted_runners?
      disabled_reason == :business_uses_only_self_hosted_runners && !page.nojekyll?
    end

    def is_legacy_build?
      disabled_reason.present? && !page.nojekyll?
    end

    def learn_more_link
      "#{GitHub.help_url}/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository"
    end

    def is_feature_flag_enabled?
      GitHub.flipper[:pages_legacy_build_infra].enabled?(@repository) || GitHub.flipper[:pages_legacy_build_infra].enabled?(@repository.owner)
    end

    def is_past_june_2024?
      Time.now.utc > SHUTDOWN_DEADLINE
    end
  end
end
