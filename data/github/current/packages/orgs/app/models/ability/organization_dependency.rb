# typed: true
# frozen_string_literal: true

module Ability::OrganizationDependency
  extend ActiveSupport::Concern

  included do
    T.bind(self, T.class_of(ActiveRecord::Base))

    scope :organization_memberships_for_user, ->(actor_id:) {
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
end
