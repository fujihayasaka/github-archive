# typed: true
# frozen_string_literal: true

class AddUsersOrganizationOrchestration < OrganizationOrchestration
  include GitHub::Memoizer

  step :create_abilities, max_attempts: 3 do
    action = data[:action].to_sym
    caller_type = data[:caller_type]
    business&.add_user_accounts(user_ids) unless GitHub.single_business_environment?

    memberships = Organization.add_users_to_organizations(user_ids: user_ids, organization_ids: organization_ids, action: action, actor: actor, caller_type: caller_type, team_ids: team_ids)

    return :skipped if memberships.empty?
  end

  step :add_organization_membership_entry do
    caller_type = data[:caller_type]
    organizations.each do |org|
      if team_ids.any?
        teams.each do |team|
          # TODO update for BusinessTeam with multiple organization_ids
          next unless team.organization_id == org.id
          with_write do
            org.bulk_add_organization_membership_entry(user_ids: user_ids, team: team, adder: actor, caller_type: caller_type)
          end
        end
      else
        with_write do
          org.bulk_add_organization_membership_entry(user_ids: user_ids, team: nil, adder: actor, caller_type: caller_type)
        end
      end
    end
  end

  job_start

  step :update_license_usage do
    return if GitHub.single_business_environment? || data[:skip_license_usage_update] == true

    business&.update_license_usage
  end

  step :update_business_user_account_attributes do
    return if GitHub.single_business_environment?
    return if business.nil?

    BusinessUserAccountUpdateAttributesJob.perform_later(business, user_account_ids: T.must(business).user_accounts.where(user_id: user_ids).pluck(:id))
  end

  step :update_organization_collaborators do
    OrganizationCollaborator.where(organization_id: organization_ids, user_id: user_ids).destroy_all
  end

  step :publicize_org_memberships do
    return unless GitHub.default_org_membership_visibility_public?

    organizations.each do |org|
      org.bulk_publicize_members(users, skip_user_synchronize_index: true)
    end
  end

  step :admin_added_email do
    return if data[:action].to_sym != :admin || data[:skip_notifications] == true

    organizations.each do |org|
      users.each do |user|
        OrganizationMailer.admin_added(user, org, actor).deliver_later
      end
    end
  end

  step :synchronize_user_search_index do
    users.each do |user|
      user.synchronize_search_index
    end
  end

  step :clear_user_contribution_caches do
    users = self.users.to_a
    return if users.none?
    with_write { Contribution.bulk_clear_caches_for_users(users, context: "AddUsersOrganizationOrchestration") }
  end

  step :mailchimp_team_list_update do
    return unless GitHub.mailchimp_enabled?

    organizations.each do |org|
      users.each do |user|
        MailchimpTeamListJob.perform_later(user: user, org: org)
      end
    end
  end

  step :update_integration_installation_rate_limits do
    organizations.each do |org|
      IntegrationInstallation.where(target: org).pluck(:id).each do |installation_id|
        UpdateIntegrationInstallationRateLimitJob.perform_later(installation_id)
      end
    end
  end

  step :instrument_add_members do
    return if data[:skip_instrumentation]

    action = data[:action].to_sym
    caller_type = data[:caller_type]
    invitation = data[:invitation_id].present? ? OrganizationInvitation.find_by(id: data[:invitation_id].to_i) : nil
    users = self.users.to_a
    organizations.each do |org|
      org.instrument_add_members(users, action, actor, invitation, caller_type)
    end
  end

  step :set_enterprise_cloud_trial do
    users = self.users.to_a
    organizations.each do |org|
      EnterpriseCloudTrialNoticeForNewMembersJob.perform_later(users) if org.business_plus?
    end
  end
end
