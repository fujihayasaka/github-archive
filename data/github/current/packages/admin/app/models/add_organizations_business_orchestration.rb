# typed: true
# frozen_string_literal: true

class AddOrganizationsBusinessOrchestration < BusinessOrchestration
  BATCH_SIZE = 100

  step :upsert_organization_memberships do
    previous_plans = {}
    organizations.each do |organization|
      previous_plans[organization.id] = organization.plan.name

      if data[:ensure_sufficient_licenses]
        T.must(business).ensure_sufficient_licenses_for_organization!(organization)
      end

      membership = T.must(business).upsert_organization_membership(organization, data[:organization_upgrade])

      if !membership.valid?
        raise Business::CannotAddOrganizationError.new(membership.errors.full_messages.to_sentence)
      end

      # Configure tenant for organization
      if T.must(business).team_sync_enabled? && membership.valid?
        UpdateTeamSyncForBusinessOrganizationJob.perform_later(org_id: organization.id)
      end
    end
    data[:previous_plans] = previous_plans
  end

  job_start

  step :instrument do
    organizations.each do |organization|
      GlobalInstrumenter.instrument("enterprise_account.organization_add", {
        enterprise_id: T.must(business).id,
        organization_id: organization.id,
        actor_id: actor&.id,
        new_organization: data[:new_organization],
        previous_plan: data[:previous_plans][organization.id]
      })

      if T.must(business).feature_flag_enabled?(:enterprise_teams_audit_logs, default: false)
        T.must(business).business_teams.where(organization_selection_type: :all).find_each(
          batch_size: BATCH_SIZE
        ) do |business_team|
          business_team.instrument :add_to_organization, org: organization, business: business
        end
      end
    end
  end

  step :restore_soft_deleted_pages do
    unless GitHub.single_or_multi_tenant_enterprise?
      organizations.each do |organization|
        RestoreSoftDeletedPagesJob.perform_later(organization)
      end
    end
  end

  step :synchronize_business_user_accounts do
    unless GitHub.single_business_environment?
      BusinessUserAccountsSynchronizeJob.perform_later(business_id: T.must(business).id)
    end
  end

  step :update_organization_collaborators do
    organizations.each do |organization|
      if T.must(business).feature_flag_enabled?(:collaborator_cache_write, default: false) ||
        organization.feature_flag_enabled?(:collaborator_cache_write, default: false)

        OrganizationCollaborator.where(organization_id: organization.id).update_all(business_id: T.must(business).id)
        OrganizationCollaboratorBackfillJob.perform_later(org: organization)
      end
    end
  end

  step :update_custom_properties do
    organizations.each do |organization|
      Repositories.domain.custom_properties.handle_org_added_to_business(
        business: T.must(business),
        org: organization
      )
    end
  end

  step :update_license_usage do
    T.must(business).update_license_usage
  end

  step :update_trade_screening_records do
    organizations.each do |organization|
      if organization.org_is_on_standard_tos?
        organization.unlink_trade_screening_record_from_org_without_actor(
          reason: "Organization added to business #{T.must(business).slug}"
        )
      else
        screening_record = organization.trade_screening_record(ignore_linked_record: true)
        if screening_record.persisted?
          screening_record.destroy(
            actor: actor,
            reason: "Organization added to business #{T.must(business).slug}"
          )
        end
      end

      T.must(business).trade_screening_record.enqueue_billing_changes
    end
  end

  step :update_enterprise_teams do
    if T.must(business).erp_feature_enabled?(:enterprise_teams_org_assignment)
      all_org_business_teams = BusinessTeam.where(business_id: T.must(business).id, organization_selection_type: "all")
      all_org_business_teams.each do |business_team|
        business_team.members_or_organizations_updated(action: :add, operation: :org)
      end

      if T.must(business).organizations.count == T.must(business).business_team_organization_assignment_limit + 1
        # snapshot org_ids here in case additional orgs are created before the scheduler decides to run the job
        org_ids = T.must(business).organization_ids.first(T.must(business).business_team_organization_assignment_limit)
        all_org_business_teams.each do |business_team|
          CreateBusinessTeamOrgAssignmentsJob.enqueue(business_team, org_ids: org_ids)
        end
      end
    end
  end
end
