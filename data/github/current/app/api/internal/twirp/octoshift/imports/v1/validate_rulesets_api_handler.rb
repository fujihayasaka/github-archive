# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::ValidateRulesetsAPIService
      class ValidateRulesetsAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelAvailability

        allow_access_for :client, allowed_clients: ["octoshift"]
        handles_service MonolithTwirp::Octoshift::Imports::V1::ValidateRulesetsAPIService

        # Public: Implementation of the CheckMigrationBypasses Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::CheckMigrationBypassesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::CheckMigrationBypassesResponse, or a Twirp::Error.
        def check_migration_bypasses(req, env)
          if req.owner_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "owner_id")
          end

          organization = replica(Organization).find_by(id: req.owner_id)
          unless organization
            return Twirp::Error.not_found(
              "Organization '#{req.owner_id}' was not found.",
              argument: "owner_id"
            )
          end

          rulesets = unbypassed_rulesets_for(organization)

          { unbypassed_rulesets: rulesets.map { |ruleset| build_ruleset_hash(ruleset) } }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        rescue Api::Internal::Twirp::Octoshift::Errors::DatastoreUnavailableForWrites => error
          datastore_unavailable_for_writes_error_handler(error.role)
        end

        private

        # Private: Find all non-disabled rulesets for the organization and its
        # parent enterprise that do NOT have a RepositoryMigrationBypassActor
        # or DeployKeyBypassActor with bypass_mode = exempt.
        #
        # organization - The Organization to query rulesets for.
        #
        # Returns an ActiveRecord::Relation of RepositoryRuleset.
        def unbypassed_rulesets_for(organization)
          sources = [organization]
          sources << organization.business if organization.business

          valid_ruleset_ids = RepositoryRulesetBypassActor
            .where(type: %w[RepositoryMigrationBypassActor DeployKeyBypassActor])
            .where(bypass_mode: RepositoryRulesetBypassActor::BYPASS_MODES[:exempt])
            .select(:repository_ruleset_id)

          RepositoryRuleset
            .where(source: sources)
            .not_disabled
            .where.not(id: valid_ruleset_ids)
            .preload(:bypass_actors)
        end

        # Private: Build a response hash for a single ruleset.
        #
        # ruleset - The RepositoryRuleset.
        #
        # Returns a Hash with :name, :owner_type, and :offense keys.
        def build_ruleset_hash(ruleset)
          {
            name: ruleset.name,
            owner_type: ruleset.source_type == "Business" ? :RULESET_OWNER_TYPE_ENTERPRISE : :RULESET_OWNER_TYPE_ORG,
            offense: migration_bypass_offense(ruleset),
          }
        end

        # Private: Determine why a ruleset is considered unbypassed.
        #
        # ruleset - The RepositoryRuleset to check.
        #
        # Returns :BYPASS_OFFENSE_NO_BYPASS if no RepositoryMigrationBypassActor or
        # DeployKeyBypassActor exists, or :BYPASS_OFFENSE_ALWAYS_ALLOW if a
        # RepositoryMigrationBypassActor exists but with bypass_mode != exempt.
        def migration_bypass_offense(ruleset)
          bypass_actor = ruleset.bypass_actors.find { |actor| actor.is_a?(RepositoryMigrationBypassActor) }

          bypass_actor ? :BYPASS_OFFENSE_ALWAYS_ALLOW : :BYPASS_OFFENSE_NO_BYPASS
        end
      end
    end
  end
end
