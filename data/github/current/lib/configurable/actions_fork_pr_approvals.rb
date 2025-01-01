# typed: false
# frozen_string_literal: true

module Configurable
  module ActionsForkPrApprovals
    # Determines which types of users require manual approval for fork pr workflows on public repositories
    # See ActionsPrivateForkPrApprovals for private repositories
    KEY = "actions_fork_pr_approvals"

    FIRST_TIME_CONTRIBUTORS = "FIRST_TIME_CONTRIBUTORS".freeze
    FIRST_TIME_CONTRIBUTOR_NEW_USERS = "FIRST_TIME_CONTRIBUTOR_NEW_USERS".freeze
    ALL_OUTSIDE_COLLABORATORS = "ALL_OUTSIDE_COLLABORATORS".freeze

    VALUES = [FIRST_TIME_CONTRIBUTORS, FIRST_TIME_CONTRIBUTOR_NEW_USERS, ALL_OUTSIDE_COLLABORATORS]
    DEFAULT_VALUE = FIRST_TIME_CONTRIBUTORS

    # API-related constants and methods
    API_VALID_POLICIES = %w[
      first_time_contributors_new_to_github
      first_time_contributors
      all_external_contributors
    ].freeze

    API_POLICY_MAPPING = {
      FIRST_TIME_CONTRIBUTOR_NEW_USERS => "first_time_contributors_new_to_github",
      FIRST_TIME_CONTRIBUTORS => "first_time_contributors",
      ALL_OUTSIDE_COLLABORATORS => "all_external_contributors"
    }.freeze

    def set_actions_fork_pr_approvals_policy(policy:, actor:)
      raise ArgumentError unless VALUES.include?(policy)
      config.set(KEY, policy, actor)

      instrument "set_actions_fork_pr_approvals_policy", actor: actor, policy: policy
    end

    def actions_fork_pr_approvals_policy
      policy = config.get(KEY)
      VALUES.include?(policy) ? policy : DEFAULT_VALUE
    end
  end
end
