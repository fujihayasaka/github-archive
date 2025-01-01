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
    business = self.business
    if business.present?
      return true if business.models_access_forced_enabled_for_child_orgs?
      return false if business.models_access_forced_disabled_for_child_orgs?
    end

    # require the org to explicitly enable/disable models access
    value = ::Configuration::Entry.targeting_user_ids(id).named(::Configurable::ModelsAccess::KEY).first&.value

    ActiveModel::Type::Boolean.new.cast(value) || false
  end

  # Public: Can this Org configure models access?
  # There are two cases:
  # 1. Enterprise owned org: depends on the business' policy
  # 2. Standalone org: can always configure models access
  sig { returns T::Boolean }
  def models_access_configurable?
    return T.must(business).models_access_configurable_for_child_orgs? if business.present?

    true
  end

  # Public: Overrides Configurable::ModelsBilling#models_billing_enabled?
  sig { returns T::Boolean }
  def models_billing_enabled?
    raw_value = ::Configuration::Entry.targeting_user_ids(id).named(::Configurable::ModelsBilling::KEY).first&.value
    value = ActiveModel::Type::Boolean.new.cast(raw_value)

    # for org that is part of an enterprise, enterprise' settings take precedence
    if business.present?
      return false unless business&.models_billing_enabled?
      return value.nil? ? true : value
    end

    # for standalone org, they are required to explicitly enable/disable models billing
    value || false
  end

  sig { returns T::Boolean }
  def custom_models_enabled?
    return false unless GitHub.models_enabled?
    return T.must(business).custom_models_enabled? if business.present?
    true
  end
end
