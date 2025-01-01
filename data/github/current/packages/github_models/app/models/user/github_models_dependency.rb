# typed: true
# frozen_string_literal: true

module User::GitHubModelsDependency
  include GitHubModels::BillingDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { User }

  included do
    T.bind(self, T.class_of(User))

    has_one :github_models_usage_details, class_name: "GitHubModels::UsageDetails", inverse_of: :user
    has_many :received_github_models_blocks, class_name: "GitHubModels::Block", inverse_of: :user
    has_many :created_github_models_blocks, class_name: "GitHubModels::Block", inverse_of: :actor
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

  # Public: Overrides Configurable::ModelsBilling#models_billing_enabled?
  sig { returns T::Boolean }
  def models_billing_enabled?
    if is_enterprise_managed?
      # For EMUs, the enterprise settings take precedence
      enterprise_managed_business&.models_billing_enabled? || false
    else
      value = ::Configuration::Entry.targeting_user_ids(id).named(::Configurable::ModelsBilling::KEY).first&.value
      ActiveModel::Type::Boolean.new.cast(value) || false
    end
  end

  # Public: Overrides Configurable::ModelsBilling#enable_models_on_billing
  sig { void }
  def enable_models_on_billing
    self.ensure_customer_and_budget(models: true)
  end

  sig { returns T::Boolean }
  def render_models_tab?
    return false if is_enterprise_managed? && enterprise_managed_business&.copilot_licensing_enabled? # If the enterprise has a special Copilot-only license, they don't get access to Models.
    return false unless can_show_models_billing?
    true
  end
end
