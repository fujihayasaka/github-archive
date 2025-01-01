# typed: true
# frozen_string_literal: true

class RemoveOrganizationsBusinessOrchestration < BusinessOrchestration
  step :uninstall_integration_installations do
    organizations.each do |organization|
      if organization.integration_installations.any?
        organization.integration_installations.includes(:integration).each do |installation|
          if installation.integration.nil? || installation.integration.internal_visibility?
            installation.uninstall(actor: actor)
          end
        end
      end
    end
  end

  step :destroy_organization_memberships do
    organizations.each do |organization|
      memberships_scope = T.must(business).organization_memberships
      if GitHub.single_business_environment?
        memberships_scope = memberships_scope.excluding_github_enterprise_org
      end
      membership = memberships_scope.find_by(organization_id: organization&.id)
      return :skipped, "#{organization} is not a member organization" unless membership

      membership.actor = actor
      membership.remove_unaffiliated_users = data[:remove_unaffiliated_users]
      membership.destroy
    end
  end

  job_start

  step :update_security_analysis_settings do
    organizations.each do |organization|
      # Clear any organization-specific GHAS licensing.
      # We previously did not support GHAS features on standalone orgs. Now we support
      # it for orgs on a Team plan, and if they are unbundled.
      if organization.advanced_security_purchased_for_entity?
        if organization.advanced_security_products_bundled? || !organization.reload.plan.business?
          # Disable GHAS on all the repositories when we remove org from business
          SecurityAnalysisSettingsUpdateJob.perform_later(
            actor: actor,
            owner: organization,
            update_type: :advanced_security_disable_all
          )

          organization.mark_advanced_security_as_not_purchased_for_entity(actor: actor)
        end
      end
    end
  end

  step :update_internal_repositories do
    organizations.each do |organization|
      valid_transfer_environment = data[:is_transfer] || GitHub.single_business_environment?

      unless valid_transfer_environment
        RemoveInternalRepositoriesJob.perform_later(organization, actor: actor)
      end
    end
  end

  step :update_private_pages do
    organizations.each do |organization|
      valid_transfer_environment = data[:is_transfer] || GitHub.single_business_environment?

      if !valid_transfer_environment && !GitHub.single_or_multi_tenant_enterprise?
        DestroyPrivatePageJob.perform_later(organization)
      end
    end
  end

  step :disable_team_sync do
    organizations.each do |organization|
      if T.must(business).team_sync_enabled? && organization.team_sync_tenant.present?
        organization.team_sync_tenant.disable
      end
    end
  end

  step :disable_source_ip_disclosure do
    organizations.each do |organization|
      if T.must(business).source_ip_disclosure_enabled?
        organization.reload
        organization.disable_source_ip_disclosure(actor: actor)
      end
    end
  end

  step :update_organization_collaborators do
    organizations.each do |organization|
      if T.must(business).feature_flag_enabled?(:collaborator_cache_write, default: false) ||
        organization.feature_flag_enabled?(:collaborator_cache_write, default: false)

        with_write { OrganizationCollaborator.where(organization_id: organization.id).update_all(business_id: nil) }
        OrganizationCollaboratorBackfillJob.perform_later(org: organization)
      end
    end
  end

  step :update_enterprise_teams do
    organizations.each do |organization|
      if T.must(business).erp_feature_enabled?(:enterprise_teams_org_assignment)
        T.must(business).business_teams.where(organization_selection_type: "all").each do |business_team|
          business_team.members_or_organizations_updated(action: :remove, operation: :org)
        end

        organization.destroy_business_team_org_assignments_in_background
      end
    end
  end

  step :update_billing do
    return unless GitHub.billing_enabled?

    organizations.each do |organization|
      # For an Organization being removed from a Business to be made an independent organization with billing enabled:
      # - Switch to self serve billing
      # - Update the organization plan to GitHub::Plan::FREE
      # - Update the plan duration to the default User::BillingDependency::MONTHLY_PLAN
      # - Change Terms of Service to our standard Terms of Service
      if GitHub.billing_enabled?
        old_billing_type = organization.billing_type

        unless old_billing_type == User::BillingDependency::CARD_BILLING_TYPE
          organization.switch_billing_type_to_card(actor)
          GitHub.instrument(
            "billing.change_billing_type",
            old_billing_type: old_billing_type,
            billing_type: organization.billing_type,
            user: organization,
            actor: actor
          )
        end

        old_plan_duration = organization.plan_duration
        if T.must(business).trial? || T.must(business).trial_expired? || T.must(business).trial_cancelled?
          old_plan = organization.reload.plan
          data[:mailer_plan] = old_plan.display_name
          organization.resume_billing
          organization.track_plan_change(actor, old_plan, { old_plan_duration: old_plan_duration })
        else
          data[:mailer_plan] = nil
          old_plan = organization.plan
          seats_was = organization.seats
          unless data[:is_transfer]
            organization.update(
              plan: GitHub::Plan::FREE,
              plan_duration: User::BillingDependency::MONTHLY_PLAN,
              seats: 0
            )
          end
          organization.terms_of_service.update(
            type: "Corporate",
            actor: actor,
            change_note: "Organization removed from the #{T.must(business).name} enterprise",
            removed_from_business: true
          )
          organization.track_plan_change(
            actor,
            old_plan,
            {
              old_plan_duration: old_plan_duration,
              filled_seats: 0,
              old_seat_count: seats_was
            }
          )
        end
      end
    end
  end

  step :disable_business_plus_features do
    return unless GitHub.billing_enabled?

    organizations.each do |organization|
      if !data[:is_transfer]
        organization.reload.disable_business_plus_features(actor: actor)
      end
    end
  end

  step :instrument do
    return if GitHub.single_business_environment?

    organizations.each do |organization|
      GlobalInstrumenter.instrument("enterprise_account.organization_remove", {
        enterprise_id: T.must(business).id,
        organization_id: organization.id,
        actor_id: actor&.id
      })
    end
  end

  step :update_custom_properties do
    organizations.each do |organization|
      # Delete the values for the business properties that are not inherited anymore
      Repositories.domain.custom_properties.handle_org_removed_from_business(
        business: T.must(business),
        org: organization
      )

      if Orgs.domain.custom_properties.feature_enabled?(T.must(business))
        Orgs.domain.custom_properties.handle_org_removed_from_business(
          business: T.must(business),
          org: organization
        )
      end
    end
  end

  step :cancel_member_organization_subscription_items do
    return unless GitHub.billing_enabled?

    organizations.each do |organization|
      if T.must(business).self_serve_payment?
        T.must(business).cancel_member_organization_subscription_items!(organization, actor: actor)
      end
    end
  end

  step :send_email_notifications do
    return unless GitHub.billing_enabled?

    organizations.each do |organization|
      if !data[:is_transfer] && organization.gh_role != "staff_delete"
        BusinessMailer.organization_removed_from_business(
          T.must(business), organization, data[:mailer_plan]
        ).deliver_later
      end
    end
  end
end
