# typed: true
# frozen_string_literal: true

class MarkNotDeletedOrganizationOrchestration < OrganizationOrchestration
  step :validate_deleted_state do
    data[:soft_deleted] = T.must(organization).soft_deleted?
    return :skipped if !(T.must(organization).deleted? || T.must(organization).soft_deleted?)
  end

  step :add_organization_to_business do
    return unless data[:soft_deleted]

    # Other soft-deleted resources are restored by `after_destroy_commit` hooks in the SoftDeletedOrganization model
    if T.must(T.must(organization).soft_deleted_organization).business_id.present?
      business = Business.find(T.must(T.must(organization).soft_deleted_organization).business_id)
      begin
        business.add_organization(T.must(organization), actor: actor)
      rescue Business::CannotAddOrganizationError => e
        raise Organization::OrganizationRestorationError, e.message
      end
    end
  end

  step :destroy_soft_deleted_organization do
    return unless data[:soft_deleted]

    T.must(organization).soft_deleted_organization&.destroy
  end

  job_start

  step :resume_billing do
    return unless data[:soft_deleted]

    # Resume billing for standalone org.
    unless T.must(organization).delegate_billing_to_business?
      T.must(organization).resume_billing
      if T.must(organization).auto_pay_reasons&.include?(:customer_initiated)
        T.must(organization).enable_auto_pay!(:customer_initiated)
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
    return :failed unless T.must(organization).legacy_mark_not_deleted(actor: actor)
  end
end
