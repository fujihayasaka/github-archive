# typed: true
# frozen_string_literal: true

module Repository::BusinessDependency
  extend T::Helpers

  include Business::TenantContext

  requires_ancestor { Repository }

  # The business that this repo is in.
  #
  # Returns nil if not in a business
  def async_business
    async_owner.then do |owner|
      owner&.async_business
    end
  end

  # Returns the id of the business that this repo is in if it has internal
  # visibility. Returns nil otherwise.
  def internal_visibility_business_id
    return internal_repository&.business_id if internal?
    nil
  end

  def has_business_owner?
    !GitHub.single_business_environment? && owner&.organization? && owner&.business.present?
  end

  def business_owner
    return unless has_business_owner?

    T.must(owner&.business)
  end

  def tenant_id
    return unless GitHub.multi_tenant_enterprise?
    @tenant_id ||= owner&.business_id
  end

  sig { override.returns(T.nilable(Business)) }
  def resolve_tenant
    GitHub::CurrentTenant.unscope { Business.find_by(id: tenant_id) }
  end

  def supports_enterprise_banner?
    owner&.organization? && owner&.business.present? \
      && GitHub.flipper[:enterprise_banners_repo_level].enabled?(owner&.business)
  end
end
