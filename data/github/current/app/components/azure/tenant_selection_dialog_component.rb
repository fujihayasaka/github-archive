# typed: strict
# frozen_string_literal: true

class Azure::TenantSelectionDialogComponent < ApplicationComponent
  include Billing::AzureOauthStateManagement

  sig { returns(Billing::Types::OrgOrBusiness) }
  attr_reader :target

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  attr_reader :tenants

  sig { returns(T::Boolean) }
  attr_reader :fetch_failed

  sig do
    params(
      target: Billing::Types::OrgOrBusiness,
      tenants: T::Array[T::Hash[Symbol, T.untyped]],
      fetch_failed: T::Boolean,
    ).void
  end
  def initialize(target, tenants, fetch_failed)
    @target = target
    @tenants = tenants
    @fetch_failed = fetch_failed
  end

  sig { override.void }
  def before_render
    @tenants.each do |t|
      t[:redirect_uri] = azure_subscription_uri(target: target, explicit_tenant_selected: true, tenant: t[:tenant_id]).to_s
    end
  end
end
