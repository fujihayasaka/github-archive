# typed: true
# frozen_string_literal: true

class SoftDeleteOrganizationOrchestration < OrganizationOrchestration
  step :update_deleted_status do
    return :skipped unless T.must(organization).permit_deletion?(actor)

    # In case organization.business has already been soft-deleted, associate the SoftDeletedOrganization
    # with the soft-deleted Business.
    business = T.must(organization).business ||
      Business.including_deleted.find_by(id: T.must(organization).business_membership&.business_id)
    data[:was_part_of_business_id] = business.id if business.present?
    SoftDeletedOrganization.create!(organization: organization, business: business)

    # We also update the data in User#raw_data to mimic a real deletion so we get
    # all the current benefits of hidden access etc.
    T.must(organization).deleted_at = Time.now
    if actor.present?
      T.must(organization).deleted_by = T.must(actor).display_login
    end
    T.must(organization).deleted = true

    T.must(organization).save!
  end

  job_start

  step :instrument do
    actor_for_instrumentation = actor.present? ? actor : User.ghost
    payload = { actor: actor_for_instrumentation, email: T.must(organization).billing_email }
    T.must(organization).add_admins_to_instrumentation
    T.must(organization).instrument(:delete, payload)

    payload.merge!(organization: organization, customer_id: Licensing::Customer.id_for(T.must(organization)))
    GlobalInstrumenter.instrument "organization.soft_delete", payload
  end

  step :remove_business_membership do
    # Remove any business membership. Code outside of Dotcom uses this to calculate user -> org -> business membership
    # so we need to make sure it's removed when the org is no longer accessible to the user.
    if data[:remove_from_business] && !T.must(organization).enterprise_managed_user_enabled?
      Business::OrganizationMembership.find_by(organization: organization)&.destroy
    end
  end

  step :suspend_owned_apps do
    T.must(organization).suspend_owned_apps
  end

  step :update_billing do
    if GitHub.billing_enabled? && !T.must(organization).delegate_billing_to_business?
      # Reset billing attempts, cancel pending plan changes, and disable auto pay before suspending billing.
      # This will be DRYed up in future so all plans, sponsors, EAs etc do this with a single call:
      # https://github.com/github/meao/issues/2777
      if T.must(organization).billing_attempts.to_i > 0
        T.must(organization).reset_billing_attempts
      end

      if T.must(organization).incomplete_pending_plan_changes.any?
        T.must(organization).incomplete_pending_plan_changes.each(&:cancel)
      end

      unless T.must(organization).auto_pay_reasons&.include?(:india_rbi)
        T.must(organization).disable_auto_pay!(:customer_initiated)
      end

      # Suspend billing for standalone org avoid any charges before it's purged.
      T.must(organization).suspend_billing
    end
  end

  step :send_email_notification do
    unless data[:site_admin_deletion]
      options = AccountMailer::Serializers.delete_org(
        organization,
        T.must(organization).admins,
        data[:was_part_of_business_id].present?
      )
      AccountMailer.delete_org(options).deliver_later

      options = AccountMailer::Serializers.delete_private(organization)
      AccountMailer.delete_private(options).deliver_later
    end
  end

  step :clear_assignments do
    # If the Organization belonged to a Business (TODO keep the if when removing the FF, then remove this comment)
    if was_part_of_business
      BusinessTeam.disassociate_org_from_teams(
        was_part_of_business.id,
        [T.must(organization)]
      )
      ClearOrganizationRoleAssignmentsJob.perform_later(
        T.must(organization).id,
        business_id: was_part_of_business.id
      )
    end
  end

  step :soft_delete_organization_repositories do
    SoftDeleteOrganizationRepositoriesJob.perform_later(T.must(organization).id)
  end

  step :soft_delete_organization_projects do
    SoftDeleteOrganizationProjectsJob.perform_later(T.must(organization).id)
  end

  private

  memoize def was_part_of_business
    if data[:was_part_of_business_id].present?
      Business.including_deleted.find_by(id: data[:was_part_of_business_id])
    end
  end
end
