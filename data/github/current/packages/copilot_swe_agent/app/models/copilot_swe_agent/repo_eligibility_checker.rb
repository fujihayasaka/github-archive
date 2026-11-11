# typed: strict
# frozen_string_literal: true

module CopilotSweAgent
  class RepoEligibilityChecker
    include GitHub::Memoizer

    sig { returns(Repository) }
    attr_accessor :repository

    sig { returns(T.nilable(T.any(Bot, User))) }
    attr_reader :viewer

    sig { params(repository: Repository, viewer: T.nilable(T.any(Bot, User))).void }
    def initialize(repository, viewer)
      @repository = repository
      @viewer = viewer
    end

    sig { params(repository: Repository, viewer: T.nilable(T.any(Bot, User))).returns(T::Boolean) }
    def self.copilot_swe_agent_eligible?(repository, viewer)
      new(repository, viewer).copilot_swe_agent_eligible?
    end

    # Returns true if the given repository/viewer combination is eligible to
    # use the Copilot SWE Agent according to feature flags and policies.
    sig { returns(T::Boolean) }
    def copilot_swe_agent_eligible?
      return false if ineligible_by_feature?

      eligible_by_feature? || eligible_by_policy?
    end

    private

    sig { returns(T::Boolean) }
    def ineligible_by_feature?
      # Public repos are ineligible unless the owner has the public repos flag
      return true if repository.public? &&
                     !repository.owner&.feature_flag_enabled_or_raise?(:copilot_swe_agent_public_repos) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

      # Repo-level disallow flag makes the repo ineligible
      return true if repository.feature_flag_enabled_or_raise?(:copilot_swe_agent_disallow) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

      false
    end

    sig { returns(T::Boolean) }
    def eligible_by_feature?
      # This FF is staff-shipped to enable staff and ensure backwards compatibility
      return true if repository.feature_flag_enabled_or_raise?(:copilot_swe_agent) || repository.owner&.feature_flag_enabled_or_raise?(:copilot_swe_agent) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

      # Returns true if the viewer is nil - this should only happen when getting twirp secrets for sweagentd
      # See /twirp/actions/core/v1/get_integration_job_secrets.rb
      return true if viewer.nil?

      # Returns true if it is Copilot, Claude, Codex agents
      if viewer.is_a?(Bot)
        return true if viewer == Apps::Privileged.integration(:copilot_swe_agent)&.bot
        return ::AgenticApp.agent_for_bot(T.cast(viewer, Bot)).present?
      end

      false
    end

    sig { returns(T::Boolean) }
    def eligible_by_policy?
      # Check copilot user policies
      viewer.is_a?(User) && Copilot::Public::User.new(T.must(viewer)).swe_agent_enabled?
    end
  end
end
