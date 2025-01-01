# typed: true
# frozen_string_literal: true

module Ability::OrganizationDependency
  extend ActiveSupport::Concern

  included do
    T.bind(self, T.class_of(ActiveRecord::Base))

    scope :direct_organization_memberships_for_user, ->(actor_id:) {
      T.bind(self, T.untyped)
      where(
        subject_type: "Organization",
        actor_id: actor_id,
        actor_type: "User",
        priority: priorities[:direct],
      )
    }

    scope :user_direct_read_on_organization, ->(actor_id:, subject_id:) {
      T.bind(self, T.untyped)
      direct.where({
        actor_id: actor_id,
        actor_type: "User",
        subject_id: subject_id,
        subject_type: "Organization",
      })
    }

    scope :user_admin_on_organization, ->(actor_id:, subject_id:) {
      T.bind(self, T.untyped)
      admin.where({
        actor_id: actor_id,
        actor_type: "User",
        subject_id: subject_id,
        subject_type: "Organization",
        priority: Ability.priorities[:direct],
      })
    }

    scope :user_admin_on_organizations, ->(actor_id:) {
      T.bind(self, T.untyped)
      admin.where({
        actor_id: actor_id,
        actor_type: "User",
        subject_type: "Organization",
        priority: Ability.priorities[:direct],
      })
    }

    scope :user_billing_manager_on_organizations, ->(actor_id:, actor_type:) {
      where(
        actor_id: actor_id,
        actor_type: actor_type,
        subject_type: "Organization::BillingManagement",
      )
    }
  end

  class_methods do
    sig { params(user_id: Integer).returns(T::Array[Integer]) }
    def organization_memberships_for_user(user_id:)
      GitHub.dogstats.distribution_time("ability.organization_dependency.organization_memberships_for_user.duration") do
        GitHub.tracer.in_span("ability.organization_dependency.organization_memberships_for_user", kind: :internal, attributes: { "gh.user.id" => user_id }) do
          indirect_member_org_ids = Orgs.domain.teams.business_team_org_ids_for_user(user_id: user_id)
          direct_member_org_ids = Ability.direct_organization_memberships_for_user(actor_id: user_id).pluck(:subject_id)

          GitHub.tracer.in_span("ability.organization_dependency.organization_memberships_for_user.build_result", kind: :internal, attributes: {
            "gh.ability.indirect_member_org_ids.size" => indirect_member_org_ids.size,
            "gh.ability.direct_member_org_ids.size" => direct_member_org_ids.size,
          }) do
            indirect_member_org_ids | direct_member_org_ids
          end
        end
      end
    end

    # Gets all organization IDs that users have access to.
    # Parameters: user_ids (Array of Integer): List of user IDs to check
    # Returns: Hash mapping user IDs to arrays of organization IDs they have access to
    sig { params(user_ids: T::Array[Integer]).returns(T::Hash[Integer, T::Array[Integer]]) }
    def organization_memberships_for_users(user_ids:)
      GitHub.dogstats.distribution_time("ability.organization_dependency.organization_memberships_for_users.duration") do
        GitHub.tracer.in_span("ability.organization_dependency.organization_memberships_for_users", kind: :internal, attributes: {
          "gh.user_ids" => user_ids.first(10),
          "gh.user_ids.size" => user_ids.size
        }) do
          # indirect memberships
          memberships_by_user = Orgs.domain.teams.business_team_org_ids_for_users(user_ids: user_ids)

          # direct memberships
          direct_memberships = Ability.direct_organization_memberships_for_user(actor_id: user_ids).pluck(:actor_id, :subject_id)

          GitHub.tracer.in_span("ability.organization_dependency.organization_memberships_for_users.build_result", kind: :internal, attributes: {
            "gh.ability.memberships_by_user.size" => memberships_by_user.size,
            "gh.ability.direct_memberships.size" => direct_memberships.size,
          }) do
            direct_memberships.each do |user_id, organization_id|
              current_memberships = (memberships_by_user[user_id] || [])
              memberships_by_user[user_id] = current_memberships | [organization_id]
            end

            memberships_by_user
          end
        end
      end
    end
  end
end
