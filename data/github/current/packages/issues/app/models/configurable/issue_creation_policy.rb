# typed: true
# frozen_string_literal: true

# Configures who can create issues.
module Configurable
  module IssueCreationPolicy
    extend ActiveSupport::Concern
    extend T::Helpers

    include ::Configurable

    requires_ancestor { IssueCreationConfig }

    KEY = "issue_creation_policy".freeze

    # Policy values
    ALL = "all".freeze
    COLLABORATORS_ONLY = "collaborators_only".freeze

    # Default policy when not set
    DEFAULT_POLICY = ALL

    # All valid policy values
    VALID_POLICIES = [
      ALL,
      COLLABORATORS_ONLY,
    ].freeze

    # Public: Set the issue creation policy.
    #
    # policy - The policy value (use ALL / COLLABORATORS_ONLY constants).
    # actor  - The User making the change.
    #
    # Returns nothing.
    def set_issue_creation_policy(policy:, actor:)
      raise ArgumentError, "Invalid policy: #{policy}" unless VALID_POLICIES.include?(policy)
      return if issue_creation_policy == policy

      config.set(KEY, policy, actor)
    end

    # Public: Get the current issue creation policy.
    #
    # Returns the policy value as a String.
    def issue_creation_policy
      config.get(KEY) || DEFAULT_POLICY
    end

    # Returns true if issue creation is restricted to collaborators only.
    # Defaults to false (anyone can create) if not set.
    def issue_creation_restricted_to_collaborators?
      issue_creation_policy == COLLABORATORS_ONLY
    end

    # Returns true if anyone can create issues.
    def issue_creation_allowed_by_all?
      issue_creation_policy != COLLABORATORS_ONLY
    end

    # Public: Check if the given user is allowed to create issues based on the policy.
    #
    # user - The User attempting to create an issue.
    #
    # Returns true if the user is allowed to create issues.
    def issue_creation_allowed_for?(user)
      repo = T.cast(repository, Repository) # rubocop:todo GitHub/AvoidCast
      return true unless FeatureFlag.vexi.enabled?(:issue_creation_restriction_settings, repo, default: false)

      case issue_creation_policy
      when COLLABORATORS_ONLY
        user_is_collaborator?(user, repo)
      else
        true
      end
    end

    private

    def user_is_collaborator?(user, repo)
      return false if user.nil? || user.is_a?(GitHub::NullUser) || user.is_a?(Bot)

      repo.pushable_by?(user)
    end
  end
end
