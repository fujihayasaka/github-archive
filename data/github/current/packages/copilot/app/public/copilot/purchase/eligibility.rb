# typed: strict
# frozen_string_literal: true

module Copilot
  # This class is designed to be used to determine the eligibility of an account (enterprise or organization)
  # to "purchase", i.e. enable, Copilot for that account.
  # Copilot cannot be purchased if:
  #   - The account is not billable
  #   - The account is on a legacy plan
  #   - The account is on a trial
  #   - The account is already enabled for Copilot
  #   - The account is an organization owned by a parent enterprise
  #   - The account is an enterprise that manages organizations on a Copilot trial
  #   - The account is a business that must be sales served
  module Purchase
    class Eligibility
      INELIGIBLE_REASON_MESSAGES = T.let({
        has_legacy_plan: "has a legacy plan",
        not_billable: "is not billable",
        has_trial: "is on a trial",
        manages_trial: "is managing organizations on a Copilot trial",
        copilot_enabled: "has already enabled Copilot",
        owned_by_parent: "is owned by a parent enterprise. Copilot can only be enabled for this organization at the enterprise level.",
        force_sales_serve: "must have it's subscription set up by sales",
        no_billing_contact_information: "does not have saved billing contact information"
      }, T::Hash[Symbol, String])

      EligibilityFactor = T.type_alias do
        {
          billable: T::Boolean,
          billed_through_parent: T::Boolean,
          copilot_enabled: T::Boolean,
          has_legacy_plan: T::Boolean,
          has_trial: T::Boolean,
          manages_trial: T::Boolean,
          owned_by_parent: T::Boolean,
          force_sales_serve: T::Boolean,

          # This is actually a compound field to catch legacy accounts that:
          #  a. Have a valid payment method
          #  b. Have never stored their billing contact information on GitHub.
          # Billing contact information is required to produce a valid trade screning record, which is now
          # a requirement for taking any action that results in commercial interaction on GitHub.
          # Because enabling Copilot will eventually result in a commercial interaction, we need to block
          # enablement until the account has valid billing information stored on our servers,
          # and thus can generate a valid trade screening record.
          no_billing_contact_information: T::Boolean
        }
      end

      EligibilityObj = T.type_alias do
        {
          organizations: T::Hash[String, EligibilityFactor],
          businesses: T::Hash[String, EligibilityFactor],
        }
      end

      EligibilityReason = T.type_alias do
        {
          eligible: T::Boolean,
          reason: Symbol
        }
      end

      sig { returns(EligibilityObj) }
      attr_reader :eligibility

      sig do
        params(
          account: T.any(::Organization, ::Business),
          orgs: T::Array[::Organization],
          businesses: T::Array[::Business]
        ).returns(EligibilityReason)
      end
      def self.for(account:, orgs: [], businesses: [])
        orgs = orgs.empty? && account.is_a?(::Organization) ? [account] : orgs
        businesses = businesses.empty? && account.is_a?(::Business) ? [account] : businesses

        new(orgs: orgs, businesses: businesses).for(account)
      end

      sig { params(factor: EligibilityReason).returns(T::Boolean) }
      def self.eligible?(factor:)
        factor[:eligible] && factor[:reason] == :ok
      end

      # It is assumed that the organizations and businesses supplied here are adminable by the current user.
      sig { params(orgs: T::Array[::Organization], businesses: T::Array[::Business]).void }
      def initialize(orgs:, businesses:)
        @eligibility = T.let(get_eligibilities(orgs, businesses), EligibilityObj)
      end

      sig { params(account: T.any(::Organization, ::Business)).returns(EligibilityReason) }
      def for(account)
        factors = lookup(account)

        return { eligible: true, reason: :ok } if factors.nil?

        reason = reason(account)

        { eligible: reason == :ok, reason: reason }
      end

      private

      sig { params(account: T.any(::Organization, ::Business)).returns(T.nilable(EligibilityFactor)) }
      def lookup(account)
        type, key = if account.is_a?(::Organization)
          [:organizations, account.display_login]
        else
          [:businesses, account.slug]
        end

        @eligibility[type][key]
      end

      sig { params(account: T.any(::Organization, ::Business)).returns(Symbol) }
      def reason(account)
        factors = lookup(account)

        return :ok unless factors.present?

        return :has_legacy_plan if factors[:has_legacy_plan]
        return :has_trial if factors[:has_trial]
        return :owned_by_parent if factors[:owned_by_parent] && account.is_a?(::Organization)
        return :manages_trial if factors[:manages_trial]
        return :force_sales_serve if factors[:force_sales_serve]
        return :not_billable unless factors[:billable]
        return :copilot_enabled if factors[:copilot_enabled]
        return :no_billing_contact_information if factors[:no_billing_contact_information]

        :ok
      end

      sig { params(orgs: T::Array[::Organization], bizs: T::Array[::Business]).returns(EligibilityObj) }
      def get_eligibilities(orgs, bizs)
        eligibilities = {
          organizations: {},
          businesses: {}
        }

        orgs.each { |org| eligibilities[:organizations][org.display_login] = org_eligibility(org) }
        bizs.each { |biz| eligibilities[:businesses][biz.slug] = biz_eligibility(biz) }

        eligibilities
      end

      sig { params(org: ::Organization).returns(EligibilityFactor) }
      def org_eligibility(org)
        eligibility = build_eligibility_factor

        copilot_org = Copilot::Organization.new(org)

        eligibility[:has_trial] = copilot_org.has_trial?
        eligibility[:manages_trial] = false
        # an org on e.g a free plan can have a trial, or one on a non-metered teams plan
        eligibility[:billable] = copilot_org.copilot_billable? ||
          eligibility[:has_trial] ||
          !!copilot_org.organization_object.has_valid_payment_method?
        eligibility[:copilot_enabled] = copilot_org.copilot_enabled?
        eligibility[:billed_through_parent] = org.is_organization_billed_through_business?
        eligibility[:has_legacy_plan] = org.plan.legacy?
        eligibility[:owned_by_parent] = org.business.present?
        eligibility[:no_billing_contact_information] =
          !!(
            !org.has_saved_trade_screening_record? &&
            eligibility[:billable] &&
            !has_azure_account?(account: org) &&
            !org.invoiced?
          )

        eligibility
      end

      sig { params(biz: ::Business).returns(EligibilityFactor) }
      def biz_eligibility(biz)
        eligibility = build_eligibility_factor

        copilot_biz = Copilot::Business.new(biz)

        eligibility[:billable] = copilot_biz.copilot_billable?
        eligibility[:copilot_enabled] = copilot_biz.copilot_enabled?
        # Enterprises can have a direct trial
        eligibility[:has_trial] = biz.trial?
        # enterprises can manage Copilot trials for their orgs
        eligibility[:manages_trial] = Copilot::Business.new(biz).all_orgs_have_active_trial?
        eligibility[:has_legacy_plan] = biz.plan.legacy?
        eligibility[:force_sales_serve] = biz.enterprise_agreements.where(status: "active").exists? &&
          biz.customer.present? &&
          biz.customer&.azure_subscription_id.nil?
        eligibility[:no_billing_contact_information] =
          !!(
            !biz.has_saved_trade_screening_record? &&
            eligibility[:billable] &&
            !has_azure_account?(account: biz) &&
            !biz.invoiced?
          )

        eligibility
      end

      sig { params(account: T.any(::Business, ::Organization)).returns(T::Boolean) }
      def has_azure_account?(account:)
        account.customer&.azure_subscription_id.present?
      end

      sig { returns(EligibilityFactor) }
      def build_eligibility_factor
        T.let({
          billable: false,
          billed_through_parent: false,
          copilot_enabled: false,
          has_legacy_plan: false,
          has_trial: false,
          manages_trial: false,
          owned_by_parent: false,
          force_sales_serve: false,
          no_billing_contact_information: false
        }, EligibilityFactor)
      end
    end
  end
end
