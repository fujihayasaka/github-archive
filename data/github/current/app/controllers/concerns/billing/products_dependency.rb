# typed: strict
# frozen_string_literal: true

module Billing::ProductsDependency
  extend T::Helpers

  include BillingSettingsHelper

  abstract!

  sig { returns(Billing::Platform::Api::Client) }
  def billing_platform_client
    Billing::Platform::Api::Client.new
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def all_products
    products_response = billing_platform_client.get_all_products
    products = if products_response.is_a?(::Billing::Platform::Api::Error)
      []
    else
      products_response[:products]
    end
    products
  end

  sig { params(this_entity: Billing::Types::Account).returns(T::Array[String]) }
  def excluded_products_for(this_entity)
    excluded = []
    case this_entity
    when Business
      excluded << "ghec" unless this_entity.metered_plan?
      excluded << "ghas" unless this_entity.advanced_security_metered_for_entity? || this_entity.has_active_advanced_security_trial? || this_entity.advanced_security_trial_enabled_for_entity?
    when Organization
      excluded << "ghec"
      excluded << "ghas" unless this_entity.advanced_security_metered_for_entity? || this_entity.advanced_security_trial_enabled_for_entity?
    when User
      excluded.concat(%w(ghec ghas))
    end

    # Exclude models when entity is billed via Azure
    excluded << "models" if this_entity.metered_via_azure?

    excluded << "spark" unless this_entity.feature_flag_enabled?(:billing_enable_spark_product, default: false)
    excluded << "coding_agent" unless this_entity.feature_flag_enabled?(:billing_enable_coding_agent_product, default: false)

    excluded
  end

  sig { params(entity: ::Billing::Types::Account).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def enabled_products(entity)
    all_products.reject { |product| excluded_products_for(entity).include?(product[:name]) }
  end
end
