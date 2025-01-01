# typed: false
# frozen_string_literal: true

module Configurable
  module ActionsRepositorySharePolicy
    # Determines how workflows and actions will be shared across enterprise
    # Note: Updated this internal repo sharing policy to allow private repo sharing too.
    #       For now, we are using the below key for both internal and private repo sharing.
    KEY = "actions_internal_repository_share_policy"

    # Raised when accessing the configuration for non-internal repositories
    class NotApplicableError < StandardError; end

    NONE = "NONE".freeze
    ACCESSIBLE_SAME_ORGANIZATION = "ACCESSIBLE_SAME_ORGANIZATION".freeze
    ACCESSIBLE_SAME_BUSINESS = "ACCESSIBLE_SAME_BUSINESS".freeze
    ACCESSIBLE_SAME_USER = "ACCESSIBLE_SAME_USER".freeze

    ENTERPRISE_ORG_OPTIONS = [NONE, ACCESSIBLE_SAME_ORGANIZATION, ACCESSIBLE_SAME_BUSINESS]
    NON_ENTERPRISE_ORG_OPTIONS = [NONE, ACCESSIBLE_SAME_ORGANIZATION]
    OUTSIDE_ORG_OPTIONS = [NONE, ACCESSIBLE_SAME_USER]
    DEFAULT_OPTION = NONE

    def set_actions_repository_share_policy(policy:, actor:)
      raise NotApplicableError unless is_actions_repository_sharing_applicable?
      raise ArgumentError unless is_option_available_for_repo(policy)

      old_policy = actions_repository_share_policy
      return if policy == old_policy

      config.set(KEY, policy, actor)
    end

    def actions_repository_share_policy
      raise NotApplicableError unless is_actions_repository_sharing_applicable?
      policy = config.get(KEY)

      return ENTERPRISE_ORG_OPTIONS.include?(policy) ? policy : DEFAULT_OPTION if self.owner.business.present?
      return NON_ENTERPRISE_ORG_OPTIONS.include?(policy) ? policy : DEFAULT_OPTION if self.owner.organization?
      OUTSIDE_ORG_OPTIONS.include?(policy) ? policy : DEFAULT_OPTION
    end

    def is_actions_repository_sharing_applicable?
      return false unless self.private?
      return true if self.internal?
      true
    end

    def is_option_available_for_repo(policy)
      return false if self.public?
      return ENTERPRISE_ORG_OPTIONS.include?(policy) if self.owner.business.present?
      return NON_ENTERPRISE_ORG_OPTIONS.include?(policy) if self.owner.organization?
      OUTSIDE_ORG_OPTIONS.include?(policy)
    end
  end
end
