# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PushAllowance < Platform::Objects::Base
      description "A team, user, or app who has the ability to push to a protected branch."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, push_allowance)
        permission.typed_can_access?("BranchProtectionRule", push_allowance.branch_protection_rule)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("BranchProtectionRule", object.branch_protection_rule)
      end

      minimum_accepted_scopes ["public_repo"]

      implements_node templates: [
        [:parbp, :repo_id, :branch_protection_rule_id],
        [:paurbp, :repo_id, :user_id, :branch_protection_rule_id],
        [:patrbp, :repo_id, :team_id, :branch_protection_rule_id],
        [:paarbp, :repo_id, :application_id, :branch_protection_rule_id]
      ], as: "PA", ready_date: Platform::Helpers::GlobalId::COHORT_2, uses_database_id: false, allow_nil_for: [:user_id, :team_id, :application_id] do |push_allowance|

        id_values = {
          repo_id: push_allowance.branch_protection_rule.repository_id,
          branch_protection_rule_id: push_allowance.branch_protection_rule.id,
        }

        case push_allowance.actor
        when ::User
          id_values.merge(prefix: :paurbp, user_id: push_allowance.actor.id)
        when ::Team
          id_values.merge(prefix: :patrbp, team_id: push_allowance.actor.id)
        when ::Integration
          id_values.merge(prefix: :paarbp, application_id: push_allowance.actor.id)
        else
          # #If the user is spammy then there will be no actor
          if push_allowance.actor.nil?
            id_values.merge(prefix: :parbp)
          else
            raise Platform::Errors::Internal, "Unexpected project owner_type: #{push_allowance.actor.inspect}"
          end
        end
      end

      field :actor, Unions::PushAllowanceActor, "The actor that can push.", null: true

      def actor
        actor = object.actor
        if actor.respond_to?(:spammy?) && actor.spammy?
          nil
        else
          actor
        end
      end

      field :branch_protection_rule, BranchProtectionRule, "Identifies the branch protection rule associated with the allowed user, team, or app.", null: true

      def self.load_from_next_global_id(parsed_id)
        prefix = parsed_id.parts[:prefix]

        unless [:paurbp, :patrbp, :paarbp].include? prefix
          raise(Platform::Errors::NotFound, "Template prefix '#{prefix}' does not match an existing global id template")
        end
        id = parsed_id.parts[:branch_protection_rule_id]

        if parsed_id.parts.include?(:user_id)
          actor_id = parsed_id.parts[:user_id]
          actor_type = "User"
        elsif parsed_id.parts.include?(:team_id)
          actor_id = parsed_id.parts[:team_id]
          actor_type = "Team"
        elsif parsed_id.parts.include?(:application_id)
          # This is type Integration however the actual type resolves to user (as in user Integration)
          actor_id = parsed_id.parts[:application_id]
          actor_type = "User"
        end

        # Spammy actors are not returned by the API and will be nil
        # This means that actor_type and actor_id could be nil;
        # there is a durable check in the model to handle this
        Models::PushAllowance.load_push_allowance(id, actor_type, actor_id)
      end

      def self.load_from_global_id(id)
        Models::PushAllowance.load_from_global_id(id)
      end
    end
  end
end
