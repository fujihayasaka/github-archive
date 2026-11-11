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
      return if entity.customer&.present?

      ensure_vnext_customer(entity)
    end

    sig { params(entity: T.any(User, Organization), tab: T.nilable(String)).void }
    def redirect_to_vnext(entity:, tab:)
      return if entity.is_a?(Organization) && entity.delegate_billing_to_business?
      return if params[:sponsorships_tab].present?

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
      return if entity.customer&.present?
      return if entity.is_a?(Organization) && entity.delegate_billing_to_business?
      return if entity.is_a?(User) && entity.is_enterprise_managed?

      log_context = { log_key(entity) => entity.id }
      tags = ["entity_type:#{entity.class.name}"]

      ActiveRecord::Base.connected_to(role: :writing) do
        Billing::CreateCustomer.perform(entity, details: {})
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
