# typed: true
# frozen_string_literal: true

module Configurable
  module RepositoryActionVerifiedOrg
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { Organization }

    KEY = "actions_marketplace_verified_org".freeze

    # Verifies the organization for repo actions. Re-indexes all repo actions from this org
    #
    # actor - user doing the action
    def verify_for_repo_actions(actor = nil)
      config.enable(KEY, actor)
      RepositoryAction.owned_by(login).each(&:synchronize_search_index)
    end

    # Removes verification from the organization for repo actions. Re-indexes all repo actions from this org
    #
    # actor - user doing the action
    def unverify_for_repo_actions(actor)
      config.disable(KEY, actor)
      RepositoryAction.owned_by(login).each(&:synchronize_search_index)
    end

    # Gets a boolean flag indicating if repo actions is enabled for this org
    #
    # Returns: boolean
    def verified_for_repo_actions?
      config.enabled?(KEY)
    end

    # Gets a relation of the organizations that are verified for repo actions
    #
    # Returns: ActiveRecord::Relation<Organization>
    def self.verified_for_repo_actions
      org_ids = Configuration::Entry.named(KEY).with_true_value.targeting_users.pluck(:target_id)
      Organization.where(id: org_ids).order(login: :asc)
    end

    # Filters org_ids verified for repo actions from the given org_ids
    #
    # Returns: An array of integers
    def self.filter_verified_org_ids(org_ids = nil)
      Configuration::Entry.targeting_user_ids(org_ids)
        .named(KEY)
        .with_true_value
        .pluck(:target_id)
    end
  end
end
