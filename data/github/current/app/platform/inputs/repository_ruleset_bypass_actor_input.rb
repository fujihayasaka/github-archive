# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class RepositoryRulesetBypassActorInput < Platform::Inputs::Base
      description "Specifies the attributes for a new or updated ruleset bypass actor. Only one of `actor_id`, `repository_role_database_id`, `organization_admin`, or `deploy_key` should be specified."

      argument :actor_id, ID, "For Team and Integration bypasses, the Team or Integration ID", required: false
      argument :repository_role_database_id, Integer, "For role bypasses, the role database ID", required: false
      argument :organization_admin, Boolean, "For organization owner bypasses, true", required: false
      argument :enterprise_owner, Boolean, "For enterprise owner bypasses, true", required: false, feature_flag: :enterprise_owner_bypass
      argument :deploy_key, Boolean, "For deploy key bypasses, true. Can only use ALWAYS as the bypass mode", required: false

      argument :bypass_mode, Enums::RepositoryRulesetBypassActorBypassMode, "The bypass mode for this actor.", required: true

      validates required: { one_of: [:actor_id, :repository_role_database_id, :organization_admin, :deploy_key, :enterprise_owner] }
    end
  end
end
