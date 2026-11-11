# typed: true
# frozen_string_literal: true

module Business::GitHubModelsDependency
  include GitHubModels::BillingDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Business }

  # Public: Enum for models access policy values
  class ModelsAccessPolicy < T::Enum
    enums do
      NO_POLICY = new("true")
      FORCE_ON = new("force_on")
      FORCE_OFF = new("false")
    end
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

  # Public: Instrumentation for forcing models access on
  sig { params(actor: User).void }
  def instrument_github_models_access_forced_on(actor:)
    # Audit log:
    instrument :github_models_access_forced_on, actor: actor
  end

  # Public: Instrumentation for forcing models access off
  sig { params(actor: User).void }
  def instrument_github_models_access_forced_off(actor:)
    # Audit log:
    instrument :github_models_access_forced_off, actor: actor
  end


  # Public: Instrumentation for forcing models access off
  sig { params(actor: User).void }
  def instrument_github_models_access_no_policy(actor:)
    # Audit log:
    instrument :github_models_access_no_policy, actor: actor
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

  sig { returns T::Boolean }
  def models_access_forced_enabled_for_child_orgs?
    value = ::Configuration::Entry.targeting_business_ids(id).named(::Configurable::ModelsAccess::KEY).first&.value

    ModelsAccessPolicy.try_deserialize(value) == ModelsAccessPolicy::FORCE_ON
  end

  sig { returns T::Boolean }
  def models_access_forced_disabled_for_child_orgs?
    value = ::Configuration::Entry.targeting_business_ids(id).named(::Configurable::ModelsAccess::KEY).first&.value

    ModelsAccessPolicy.try_deserialize(value) == ModelsAccessPolicy::FORCE_OFF
  end

  # Public: Can child orgs configure models access?
  # Child org can only configure their models access if the business/enterprise has NO_POLICY set.
  sig { returns T::Boolean }
  def models_access_configurable_for_child_orgs?
    value = ::Configuration::Entry.targeting_business_ids(id).named(::Configurable::ModelsAccess::KEY).first&.value

    ModelsAccessPolicy.try_deserialize(value) == ModelsAccessPolicy::NO_POLICY
  end

  sig { params(actor: User, instrument: T::Boolean).returns(T::Boolean) }
  def force_models_access_on(actor:, instrument: true)
    changed = set_models_access(actor, ModelsAccessPolicy::FORCE_ON.serialize, force: true)
    instrument_github_models_access_forced_on(actor: actor) if instrument && changed
    changed
  end

  sig { params(actor: User, instrument: T::Boolean).returns(T::Boolean) }
  def force_models_access_off(actor:, instrument: true)
    changed = set_models_access(actor, ModelsAccessPolicy::FORCE_OFF.serialize, force: true)
    instrument_github_models_access_forced_off(actor: actor) if instrument && changed
    changed
  end

  sig { params(actor: User, instrument: T::Boolean).returns(T::Boolean) }
  def remove_models_access_policy(actor:, instrument: true)
    changed = set_models_access(actor, ModelsAccessPolicy::NO_POLICY.serialize, force: true)
    instrument_github_models_access_no_policy(actor: actor) if instrument && changed
    changed
  end

  sig { returns ModelsAccessPolicy }
  def models_access_label
    value = ::Configuration::Entry.targeting_business_ids(id).named(::Configurable::ModelsAccess::KEY).first&.value
    # return value from configuration store, or as default return FORCE_OFF
    ModelsAccessPolicy.try_deserialize(value) || ModelsAccessPolicy::FORCE_OFF
  end

  sig { returns T::Boolean }
  def custom_models_enabled?
    value = ::Configuration::Entry.targeting_business_ids(id).named(::Configurable::CustomModels::KEY).first&.value

    ActiveModel::Type::Boolean.new.cast(value) || false
  end

  # Public: Overrides Configurable::CustomModels#instrument_github_custom_models_enablement
  sig { params(actor: User).void }
  def instrument_github_custom_models_enablement(actor:)
    # Audit log:
    instrument :github_custom_models_enabled, actor: actor
  end

  # Public: Overrides Configurable::CustomModels#instrument_github_custom_models_disablement
  sig { params(actor: User).void }
  def instrument_github_custom_models_disablement(actor:)
    # Audit log:
    instrument :github_custom_models_disabled, actor: actor
  end
end
