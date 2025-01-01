# typed: strict
# frozen_string_literal: true

module Sponsors
  module Orgs
    module PremiumDashboard
      class QuickActionsComponent < ApplicationComponent
        extend T::Sig

        sig { params(org: Organization, has_active_sponsors_agreement: T::Boolean).void }
        def initialize(org:, has_active_sponsors_agreement:)
          @org = org
          @has_active_sponsors_agreement = has_active_sponsors_agreement
        end

        private

        sig { returns(Organization) }
        attr_reader :org

        sig { returns(T::Boolean) }
        attr_reader :has_active_sponsors_agreement

        alias :has_active_sponsors_agreement? :has_active_sponsors_agreement

        sig { returns(T::Boolean) }
        def render?
          return false unless GitHub.sponsors_enabled?
          logged_in?
        end

        sig { returns(T::Boolean) }
        def self_serve_invoices_enabled?
          org.stripe_customer_id.present?
        end

        sig { returns(T::Boolean) }
        def show_sign_agreement_link?
          return false if has_active_sponsors_agreement?
          return false unless self_serve_invoices_enabled?
          org.sponsors_invoiced?
        end

        sig { returns(T::Boolean) }
        def show_create_invoice_link?
          return false if show_sign_agreement_link?
          return false unless self_serve_invoices_enabled?
          org.sponsors_invoiced?
        end
      end
    end
  end
end
