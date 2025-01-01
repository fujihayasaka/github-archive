# typed: true
# frozen_string_literal: true

module Business::GitHubModelsDependency
  include GitHubModels::BillingDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Business }

  # Public: Overrides Configurable::ModelsBilling#instrument_github_models_billing_enablement
  sig { params(actor: User).void }
  def instrument_github_models_billing_enablement(actor:)
    # Audit log:
    instrument :github_models_billing_enabled, actor: actor
  end

  # Public: Overrides Configurable::ModelsBilling#instrument_github_models_billing_disablement
  sig { params(actor: User).void }
  def instrument_github_models_billing_disablement(actor:)
    # Audit log:
    instrument :github_models_billing_disabled, actor: actor
  end

  # Public: Overrides Configurable::ModelsBilling#enable_models_on_billing
  sig { void }
  def enable_models_on_billing
    self.ensure_customer(models: true)
  end

  sig { returns T::Boolean }
  def models_access_enabled?
    value = ::Configuration::Entry.targeting_business_ids(id).named(::Configurable::ModelsAccess::KEY).first&.value

    ActiveModel::Type::Boolean.new.cast(value) || false
  end
end
