# typed: strict
# frozen_string_literal: true

class Azure::TenantSelectionDialogComponent < ApplicationComponent

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
    @tenants.each do |t|
      t[:redirect_uri] = azure_subscription_uri(explicit_tenant_selected: true, tenant: t[:tenant_id]).to_s
    end

    @fetch_failed = fetch_failed
  end

  private

  sig { params(args: T.untyped).returns(URI::HTTPS) }
  def azure_subscription_uri(**args)
    Billing::Settings::AzureMeteredBillingComponent.new(
      view: nil,
      target: target,
    ).azure_subscription_uri(**args)
  end

end
