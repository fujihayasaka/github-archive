# typed: true
# frozen_string_literal: true

module Codespaces
  class CreatePolicyGroup < Command
    extend T::Sig
    attr_reader :name, :owner, :universal_membership, :target_type, :target_ids, :constraints, :context, :actor

    sig { params(name: String, owner: T.any(Organization, Business), target_type: Symbol, universal_membership: T::Boolean, target_ids: T::Array[Integer], constraints: T::Array[Hash], context: T::Hash[String, String], actor: T.nilable(::User)).void }
    def initialize(name:, owner:, target_type:, universal_membership: false, target_ids: [], constraints: [], context: {}, actor: nil)
      raise ArgumentError, "Invalid target type: #{target_type}" unless %i(repositories organizations).include?(target_type)
      @name = name
      @owner = owner
      @universal_membership = universal_membership # If true, the policy group applies to all of the owner's repositories or organizations, the target ID list is ignored.
      @target_type = target_type # :repositories, or :organizations
      @target_ids = target_ids
      @constraints = constraints
      @context = context
      @actor = actor
    end

    def perform
      policy_group = T.let(nil, T.nilable(Codespaces::PolicyGroup))

      Codespaces::PolicyGroup.transaction do
        policy_group = Codespaces::PolicyGroup.create!(name: name, owner: owner)

        applied_target_ids = []
        if universal_membership
          policy_group.apply_universal_membership!
        else
          applied_target_ids = policy_group.apply_entity_allowlist_membership!(target_ids, target_type)
        end

        policy_constraints = policy_group.apply_constraints!(constraints)

        context.merge!(instrumentation_context(policy_group, policy_constraints, target_ids: applied_target_ids))
        policy_group
      end

      GitHub.instrument("codespaces.policy_group_created", context)
      GitHub.dogstats.increment("codespaces.policy_group.created", tags: ["membership:#{universal_membership ? "all_#{target_type}" : "selected_#{target_type}"}"])

      policy_group
    end

    private

    def instrumentation_context(policy_group, policy_constraints, target_ids:)
      {
        actor: actor,
        policy_group_id: policy_group.id,
        policy_group_name: policy_group.name,
        policy_constraints: policy_constraints.map(&:audit_log_data),
      }.merge(owner_instrumentation_context(target_ids))
    end

    def owner_instrumentation_context(target_ids)
      if owner.is_a?(Organization)
        {
          org: owner,
          all_repositories: universal_membership,
          repository_nwos: owner.repositories.where(id: target_ids).map(&:name_with_display_owner).sort || [],
          repository_ids: target_ids,
        }
      elsif owner.is_a?(Business)
        {
          business: owner,
          all_organizations: universal_membership,
          org_logins: owner.organizations.where(id: target_ids).map(&:display_login).sort || [],
          org_ids: target_ids,
        }
      else
        {}
      end
    end
  end
end
