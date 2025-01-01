# typed: true
# frozen_string_literal: true

module Organization::GitHubModelsDependency
  include GitHubModels::BillingDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Organization }

  included do
    T.bind(self, T.class_of(Organization))

    has_many :github_models_access_rules, class_name: "GitHubModels::OrganizationAccessRule", inverse_of: :organization
  end

  # Public: Overrides Configurable::ModelsAccess#instrument_github_models_enablement
  sig { params(actor: User).void }
  def instrument_github_models_enablement(actor:)
    # Audit log:
    instrument :github_models_enabled, actor: actor
  end

  # Public: Overrides Configurable::ModelsAccess#instrument_github_models_disablement
  sig { params(actor: User).void }
  def instrument_github_models_disablement(actor:)
    # Audit log:
    instrument :github_models_disabled, actor: actor
  end

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
    self.ensure_customer_and_budget(models: true)
  end


  sig { returns T::Boolean }
  def models_access_enabled?
    if business.present?
      return false unless business&.models_access_enabled?
    end

    # require the org to explicitly enable/disable models access
    value = ::Configuration::Entry.targeting_user_ids(id).named(::Configurable::ModelsAccess::KEY).first&.value

    ActiveModel::Type::Boolean.new.cast(value) || false
  end

  sig { returns T::Boolean }
  def models_access_configurable?
    return T.must(business).models_access_enabled? if business.present?

    true
  end
end
