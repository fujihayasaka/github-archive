# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::PeopleController < Stafftools::Businesses::BusinessBaseController
  skip_before_action :dotcom_required
  before_action :check_for_owners
  include BusinessesHelper
  include EnterpriseManagedUsersHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    render "stafftools/businesses/people", locals: {
      members_count: this_business.filtered_members(current_user, ignore_org_membership_visibility: true, batched_scope: true).count,
      suspended_members_count: this_business.write_through_cache.get_and_update(:suspended_members, type: :int, pluck: :id)&.count,
      pending_members_count: this_business.unique_pending_member_invitation_count,
      unassigned_user_bundled_license_assignments_count: this_business.unassigned_user_bundled_license_assignments_count,
      bundled_license_assignments_count: this_business.bundled_license_assignments.count,
      unassigned_license_assignments_count: this_business.unassigned_user_bundled_license_assignments_count,
      assigned_license_assignments_count: this_business.assigned_user_bundled_license_assignments_count,
      repository_collaborators_count: this_business&.emu_repository_collaborators_enabled? ? this_business.user_accounts.roles(:outside_collaborator).count : 0,
      guest_collaborators_count: this_business.enterprise_managed_user_enabled? ? this_business.write_through_cache.get_and_update(:all_guest_collaborators, type: :int, pluck: :id).count : 0,
      public_outside_collaborators_count: this_business.enterprise_managed_user_enabled? ? 0 : this_business.write_through_cache.get_and_update(:filtered_outside_collaborators, { visibility: [:public] }, type: :int, pluck: :id).count,
      private_outside_collaborators_count: this_business.enterprise_managed_user_enabled? ? 0 : this_business.write_through_cache.get_and_update(:filtered_outside_collaborators, { visibility: [:private] }, type: :int, pluck: :id).count,
      pending_outside_collaborators_count: this_business.pending_collaborator_invitations.count,
      support_entitlees_count: this_business.support_entitlees.count,
      owners_count: this_business.owners.count,
      unaffiliated_count: this_business.user_accounts.exclusive_unaffiliated_role.count,
      pending_owner_invitations_count: this_business.pending_admin_invitations(role: [:owner]).count,
      expired_owner_invitations_count: this_business.invitations.expired.with_business_role(:owner).count,
      billing_managers_count: this_business.billing_managers.count,
      pending_billing_managers_invitations_count: this_business.pending_admin_invitations(role: [:billing_manager]).count,
      user_namespace_repositories_count: this_business.write_through_cache.get_and_update(:user_namespace_repositories_ids)&.count,
      user_dormancy_reports: GHECAdmin::EnterpriseDormantUsersExport.latest_for_business(business: this_business, include_stafftools_reports: true),
      user_dormancy_reports_url: dormant_users_exports_stafftools_enterprise_path(this_business)
    }
  end
end
