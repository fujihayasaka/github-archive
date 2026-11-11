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

    # For org-owned repos that are not eligible, the viewer may have requested that an org/enterprise admin
    # grant access to the Copilot SWE Agent.
    sig { returns(T::Boolean) }
    def viewer_has_requested_swe_agent?
      return false if viewer.nil?
      return false unless repository_org_owner.present?

      # Check if the viewer has requested access to the org
      return true if MemberFeatureRequest.already_requested?(T.must(viewer), T.must(repository_org_owner), MemberFeatureRequest::Feature::CopilotCodingAgent)

      # If the viewer is an org admin and the org has a business, also check if they've requested to the enterprise
      if viewer_is_owning_org_admin? && (business = T.must(repository_org_owner).business)
        return true if MemberFeatureRequest.already_requested?(T.must(viewer), T.must(repository_org_owner), MemberFeatureRequest::Feature::CopilotCodingAgent, business)
      end

      false
    end

    # For org-owned repos that are not eligible, the viewer may be able to request that an org/enterprise admin
    # grant access to the Copilot SWE Agent.
    sig { returns(T::Boolean) }
    def viewer_can_request_swe_agent?
      return false unless viewer_has_copilot_seat? || viewer_is_owning_org_admin?
      return false unless swe_agent_requestable?
      return false if viewer_has_requested_swe_agent?

      return false if viewer_can_write_enterprise_copilot_settings?
      if !T.must(copilot_org).swe_agent_policy_inherited?
        !viewer_is_owning_org_admin?
      else
        true
      end
    end

    # For org-owned repos that are not eligible, the viewer may be an org admin that is able to
    # grant access to the Copilot SWE Agent, depending on the enterprise's swe_agent policy.
    sig { returns(T::Boolean) }
    def viewer_can_grant_org_swe_agent?
      return false unless swe_agent_requestable?

      return false unless viewer_is_owning_org_admin?
      !T.must(copilot_org).swe_agent_policy_inherited?
    end

    # For org-owned repos that are not eligible, the viewer may be an enterprise admin that is able to
    # grant access to the Copilot SWE Agent.
    sig { returns(T::Boolean) }
    def viewer_can_grant_enterprise_swe_agent?
      return false unless swe_agent_requestable?

      viewer_can_write_enterprise_copilot_settings?
    end

    private

    sig { returns(T.nilable(Organization)) }
    memoize def repository_org_owner
      return unless repository_owner = repository.owner
      return unless repository_owner.organization?
      T.cast(repository_owner, Organization)
    end

    sig { returns(T.nilable(Copilot::Organization)) }
    memoize def copilot_org
      if repository_org_owner.present?
        Copilot::Organization.new(T.must(repository_org_owner))
      end
    end

    sig { returns(T::Boolean) }
    def viewer_is_affiliated_with_owning_org?
      return false if viewer.nil?

      viewer_is_owning_org_member? ||
        viewer_is_owning_org_admin? ||
        viewer_can_write_enterprise_copilot_settings?
    end

    sig { returns(T::Boolean) }
    memoize def viewer_is_owning_org_member?
      return false if viewer.nil?

      if repository_org_owner
        T.must(repository_org_owner).member?(viewer)
      else
        false
      end
    end

    sig { returns(T::Boolean) }
    memoize def viewer_is_owning_org_admin?
      return false if viewer.nil?

      if repository_org_owner
        T.must(repository_org_owner).adminable_by?(viewer)
      else
        false
      end
    end

    sig { returns(T::Boolean) }
    memoize def viewer_can_write_enterprise_copilot_settings?
      return false if viewer.nil?
      return false unless business = repository_org_owner&.business

      Authz.domain.check_allowed(T.must(viewer), :write_enterprise_copilot_settings, business)
    end

    sig { returns(T::Boolean) }
    memoize def viewer_has_copilot_seat?
      return false if viewer.nil?
      return false unless viewer.is_a?(User)

      org = copilot_org
      return false unless org

      org.has_seat_for?(T.cast(viewer, User))
    end

    # Returns true if the repo is org-owned, does not currently have sweagent enabled, and the viewer
    # may be able to request or grant access to the Copilot SWE Agent.
    sig { returns(T::Boolean) }
    def swe_agent_requestable?
      return false unless viewer_is_affiliated_with_owning_org?
      # Ineligible by feature means SWE agent does not have access via flag so not requestable
      # Eligible by feature means SWE agent access is already granted via flag so not requestable
      return false if ineligible_by_feature? || eligible_by_feature?
      return false if copilot_org&.swe_agent_enabled?

      true
    end

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

      # The Copilot bot actor is always eligible
      return true if viewer.is_a?(Bot) && viewer == Apps::Privileged.integration(:copilot_swe_agent)&.bot

      false
    end

    sig { returns(T::Boolean) }
    def eligible_by_policy?
      # Check copilot user policies
      viewer.is_a?(User) && Copilot::Public::User.new(T.must(viewer)).swe_agent_enabled?
    end
  end
end
