# typed: strict
# frozen_string_literal: true

module Billing
  module BillingChecksDependency
    extend ActiveSupport::Concern
    extend T::Helpers

    requires_ancestor { ApplicationController }

    SPENDING_LIMIT_TAB = T.let("spending_limit", String)

    sig { params(entity: ::Billing::Types::Account).void }
    def ensure_vnext_enabled(entity:)
      return if entity.billed_via_billing_platform?

      if entity.feature_enabled?(:billing_vnext_default_onboarding)
        ensure_vnext_customer(entity)
      else
        if entity.is_a?(Business)
          render_404
        elsif entity.is_a?(Organization)
          redirect_to(settings_org_billing_path(entity))
        else
          redirect_to(:settings_user_billing)
        end
      end
    end

    sig { params(entity: T.any(User, Organization), tab: T.nilable(String)).void }
    def redirect_to_vnext(entity:, tab:)
      return unless entity.feature_enabled?(:billing_vnext_default_onboarding)
      return if entity.is_a?(Organization) && entity.delegate_billing_to_business?

      if tab == SPENDING_LIMIT_TAB
        redirect_to vnext_budgets_path(entity: entity)
      elsif tab.blank?
        redirect_to vnext_overview_path(entity: entity)
      else
        ensure_vnext_customer(entity)
      end
    end

    sig { params(entity: ::Billing::Types::Account).void }
    def ensure_vnext_customer(entity)
      return if !entity.feature_enabled?(:billing_vnext_default_onboarding) || entity.billed_via_billing_platform?
      return if entity.is_a?(Organization) && entity.delegate_billing_to_business?

      log_context = { log_key(entity) => entity.id }
      tags = ["entity_type:#{entity.class.name}"]

      ActiveRecord::Base.connected_to(role: :writing) do
        customer = if entity.customer
          entity.customer
        else
          GitHub.logger.info("Creating a new customer from billing settings", log_context)
          GitHub.dogstats.increment("billing.customer_created_from_settings.count", tags: tags)
          Billing::CreateCustomer.perform(entity, details: {}).customer
        end

        unless customer&.billed_via_billing_platform?
          GitHub.logger.info("Onboarding customer to all billing platform products from billing settings", log_context)
          GitHub.dogstats.increment("billing.customer_onboarded_to_vnext_from_settings.count", tags: tags)
          T.must(customer).onboard_to_all_billing_platform_products
        end
      end
    end

    sig { params(entity: ::Billing::Types::Account).returns(String) }
    def log_key(entity)
      if entity.is_a?(Organization)
        "gh.org.id"
      elsif entity.is_a?(Business)
        "gh.business.id"
      else
        "gh.user.id"
      end
    end

    sig { params(entity: T.any(User, Organization)).returns(String) }
    def vnext_budgets_path(entity:)
      if entity.is_a?(Organization)
        organization_settings_billing_budgets_path(organization_id: entity.display_login)
      else
        settings_billing_budgets_path
      end
    end

    sig { params(entity: T.any(User, Organization)).returns(String) }
    def vnext_overview_path(entity:)
      if entity.is_a?(Organization)
        organization_settings_billing_path(organization_id: entity.display_login)
      else
        settings_billing_path
      end
    end
  end
end
