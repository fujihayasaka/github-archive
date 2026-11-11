# typed: true
# frozen_string_literal: true

class MarkNotDeletedOrganizationOrchestration < OrganizationOrchestration
  step :validate_deleted_state do
    data[:soft_deleted] = T.must(organization).soft_deleted?
    return :skipped if !(T.must(organization).deleted? || T.must(organization).soft_deleted?)
    # Capture the soft-delete timestamp before any subsequent step clears it;
    # used to enqueue restore jobs.
    data[:soft_deleted_at_ts] = T.must(organization).soft_deleted_at&.to_i
  end

  step :add_organization_to_business do
    return unless data[:soft_deleted]

    business = T.must(organization).business_id > 0 ? Business.find(T.must(organization).business_id) : nil

    if business.present?
      begin
        business.add_organization(T.must(organization), actor: actor)
      rescue Business::CannotAddOrganizationError, Business::CannotAddUserAccountError => e
        raise Organization::OrganizationRestorationError, e.message
      end
    end
  end

  step :clear_soft_deleted_at do
    return unless data[:soft_deleted]
    org = T.must(organization)
    return if org.soft_deleted_at.nil?

    columns = { soft_deleted_at: nil }
    # rubocop:disable GitHub/DoNotAllowLogin -- Use login to repair display_login values corrupted by the old stafftools restore path.
    expected_display_login = T.must(User.display_login_without_shortcode(org.login, tenant: nil))
    if GitHub::CurrentTenant.stafftools_tenant? &&
       FeatureFlag.vexi.enabled?(:repair_corrupt_org_display_login_on_restore, org.business, default: false) &&
       org.display_login == org.login &&
       expected_display_login != org.login
      columns[:display_login] = expected_display_login
    end
    # rubocop:enable GitHub/DoNotAllowLogin

    # Bypass callbacks so stafftools restores do not recompute `display_login`
    # from the suffixed login.
    with_write { org.update_columns(columns) }
  end

  step :enqueue_restore_jobs do
    return unless data[:soft_deleted]

    timestamp = data[:soft_deleted_at_ts]
    return unless timestamp

    org_id = T.must(organization).id
    RestoreSoftDeletedOrganizationProjectsJob.perform_later(org_id, timestamp)
    RestoreSoftDeletedOrganizationRepositoriesJob.perform_later(org_id, timestamp)
  end

  job_start

  step :resume_billing do
    return unless data[:soft_deleted]

    # Resume billing for standalone org.
    unless T.must(organization).delegate_billing_to_business?
      T.must(organization).resume_billing
      if T.must(organization).auto_pay_reasons&.include?(:customer_initiated)
        with_write { T.must(organization).enable_auto_pay!(:customer_initiated) }
      end
    end
  end

  step :instrument do
    return unless data[:soft_deleted]

    GlobalInstrumenter.instrument "organization.restore", {
      actor: actor,
      organization: T.must(organization),
      customer_id: Licensing::Customer.id_for(T.must(organization)),
    }
  end

  step :legacy_mark_not_deleted do
    return :failed unless with_write { T.must(organization).legacy_mark_not_deleted(actor: actor) }
  end
end
