# typed: true
# frozen_string_literal: true

class RemoveOrganizationsBusinessOrchestration < BusinessOrchestration
  step :uninstall_integration_installations do
    organizations.each do |organization|
      if organization.integration_installations.any?
        organization.integration_installations.includes(:integration).each do |installation|
          if installation.integration.nil? || installation.integration.internal_visibility?
            with_write { installation.uninstall(actor: actor) }
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
      with_write { membership.destroy }
    end
  end

  job_start

  step :update_security_analysis_settings do
    business = T.must(self.business)

    organizations.each do |organization|
      # Clear any organization-specific GHAS licensing.
      # We previously did not support GHAS features on standalone orgs. Now we support
      # it for orgs on a Team plan, and if they are unbundled.
      ghas_purchased = organization.advanced_security_purchased_for_entity?
      ghas_bundled = organization.advanced_security_products_bundled?
      ghas_disabled = false

      if ghas_purchased
        org_on_business_plan = organization.reload.plan.business?

        if ghas_bundled || !org_on_business_plan
          # Disable GHAS on all the repositories when we remove org from business
          SecurityAnalysisSettingsUpdateJob.perform_later(
            actor: actor,
            owner: organization,
            update_type: :advanced_security_disable_all
          )

          with_write { organization.mark_advanced_security_as_not_purchased_for_entity(actor: actor) }
          ghas_disabled = true
        end
      end

      # Observability: track every org removal with tags that capture GHAS state.
      # Filter to ghas_purchased:true,ghas_disabled:false to find leaks.
      #
      # See: https://github.com/github/security-products-enablement/issues/2494
      begin
        if FeatureFlag.vexi.enabled?("free_org_ghas_leak_observability", default: false)
          org_plan = organization.plan.name
          has_dfd_trial = business.dfd_trial?
          has_ghas_trial = business.has_active_advanced_security_trial?
          business_trial = business.trial?
          business_trial_expired = business.trial_expired?
          is_transfer = !!data[:is_transfer]

          GitHub.dogstats.increment(
            "free_org_ghas_leak_observability.org_removed",
            tags: [
              "ghas_purchased:#{ghas_purchased}",
              "ghas_bundled:#{ghas_bundled}",
              "org_plan:#{org_plan}",
              "ghas_disabled:#{ghas_disabled}",
              "has_dfd_trial:#{has_dfd_trial}",
              "has_ghas_trial:#{has_ghas_trial}",
              "business_trial:#{business_trial}",
              "business_trial_expired:#{business_trial_expired}",
              "is_transfer:#{is_transfer}",
            ]
          )
          GitHub.logger.info(
            "free_org_ghas_leak_observability.org_removed",
            "gh.org.id": organization.id,
            "gh.org.login": organization.display_login,
            "gh.org.plan": org_plan,
            "gh.org.ghas_purchased": ghas_purchased,
            "gh.org.ghas_bundled": ghas_bundled,
            "gh.org.ghas_disabled": ghas_disabled,
            "gh.business.id": business.id,
            "gh.business.slug": business.slug,
            "gh.business.has_dfd_trial": has_dfd_trial,
            "gh.business.has_ghas_trial": has_ghas_trial,
            "gh.business.trial": business_trial,
            "gh.business.trial_expired": business_trial_expired,
            "gh.is_transfer": is_transfer,
          )
        end
      rescue => error
        Failbot.report(error, context: "free_org_ghas_leak_observability")
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
        with_write { organization.team_sync_tenant.disable }
      end
    end
  end

  step :disable_source_ip_disclosure do
    organizations.each do |organization|
      if T.must(business).source_ip_disclosure_enabled?
        organization.reload
        with_write { organization.disable_source_ip_disclosure(actor: actor) }
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

  step :update_organization_invitations do
    return if GitHub.bypass_org_invites_enabled? || T.must(business).enterprise_managed?
    with_write do
      OrganizationInvitation.where(
          organization: organization_ids
        ).update_all(business_id: nil)
    end
  end

  step :update_enterprise_teams do
    with_write do
      if FeatureFlag.vexi.enabled?(:business_team_org_assignments_domain, T.must(business), default: false)
        Orgs.domain.business_team_org_assignments.disassociate_org_from_teams(business_id: business_id, org_ids: organizations.map(&:id))
      else
        BusinessTeam.disassociate_org_from_teams(business_id, organizations)
      end
    end
  end

  step :update_organization_role_assignments do
    return unless OrganizationRole.where(owner_type: "Business", owner_id: business_id).exists?

    organizations.each do |organization|
      RemoveBusinessOrgRoleAssignmentsJob.perform_later(business_id, organization.id)
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

        if old_billing_type != User::BillingDependency::CARD_BILLING_TYPE
          with_write { organization.switch_billing_type_to_card(actor) }
          GitHub.instrument(
            "billing.change_billing_type",
            old_billing_type: old_billing_type,
            billing_type: organization.billing_type,
            user: organization,
            actor: actor
          )
        else
          if (customer = organization.customer) && customer.business.present?
            with_write { organization.customer_accounts.destroy_by(customer_id: customer.id) }
            with_write { organization.plan_subscription&.clear_external_subscription_references }
          end
        end

        old_plan_duration = organization.plan_duration
        if T.must(business).trial? || T.must(business).trial_expired? || T.must(business).trial_cancelled?
          old_plan = organization.reload.plan
          data[:mailer_plan] = old_plan.display_name
          with_write { organization.resume_billing }
          with_write { organization.track_plan_change(actor, old_plan, { old_plan_duration: old_plan_duration }) }
        else
          data[:mailer_plan] = nil
          old_plan = organization.plan
          seats_was = organization.seats
          unless data[:is_transfer]
            with_write do
              organization.update(
                plan: GitHub::Plan::FREE,
                plan_duration: User::BillingDependency::MONTHLY_PLAN,
                seats: 0
              )
            end
          end
          with_write do
            organization.terms_of_service.update(
              type: "Corporate",
              actor: actor,
              change_note: "Organization removed from the #{T.must(business).name} enterprise",
              removed_from_business: true
            )
          end
          with_write do
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
  end

  step :disable_business_plus_features do
    return unless GitHub.billing_enabled?

    organizations.each do |organization|
      if !data[:is_transfer]
        with_write { organization.reload.disable_business_plus_features(actor: actor) }
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

    GlobalInstrumenter.instrument("enterprise_account.remove_organizations", {
      enterprise: business,
      actor: actor,
      organization_ids: organization_ids
    })
  end

  step :update_custom_properties do
    organizations.each do |organization|
      with_write do
        # Delete the values for the business properties that are not inherited anymore
        Repositories.domain.custom_properties.handle_org_removed_from_business(
          business: T.must(business),
          org: organization
        )

        Orgs.domain.custom_properties.handle_org_removed_from_business(
          business: T.must(business),
          org: organization
        )
      end
    end
  end

  step :update_blackbird do
    BlackbirdOnboardJob.perform_later(organizations.to_a)
  end

  step :cancel_member_organization_subscription_items do
    return unless GitHub.billing_enabled?

    organizations.each do |organization|
      if T.must(business).self_serve_payment?
        with_write { T.must(business).cancel_member_organization_subscription_items!(organization, actor: actor) }
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
