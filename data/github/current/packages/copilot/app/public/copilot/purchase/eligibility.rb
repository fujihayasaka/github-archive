# typed: strict
# frozen_string_literal: true

module Copilot
  # This class is designed to be used to determine the eligibility of an account
  # to "purchase", i.e. enable, Copilot for that account.
  # It is not necessarily intended to be used to determine eligibility for ANY type
  # of Copilot-related action.
  module Purchase
    class Eligibility
      ELIGIBILITY_REASON_MESSAGES = T.let({
        has_legacy_plan: "has a legacy plan",
        not_billable: "is not billable",
        has_trial: "is on an Enterprise trial or managing organizations on Copilot trials",
        copilot_enabled: "has already enabled Copilot",
        copilot_disabled_by_parent: "has had Copilot access disabled by the parent enterprise",
        no_trade_screening_record: "has not linked an owner's billing account information",
        owned_by_parent: "is owned by a parent enterprise. Copilot can only be enabled for this organization at the enterprise level.",
      }, T::Hash[Symbol, String])

      EligibilityFactor = T.type_alias do
        {
          billable: T::Boolean,
          billed_through_parent: T::Boolean,
          copilot_disabled_by_parent: T::Boolean,
          copilot_enabled: T::Boolean,
          has_legacy_plan: T::Boolean,
          has_trial: T::Boolean,
          has_trade_screen: T::Boolean,
          owned_by_parent: T::Boolean,
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
          reason: T.nilable(Symbol)
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

      # For now, it is assumed that the organizations and businesses supplied to this
      # constructor are adminable by the current user who made the request which led to this object
      # being instantiated.
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

      sig { params(account: T.any(::Organization, ::Business)).returns(T.nilable(Symbol)) }
      def reason(account)
        factors = lookup(account)

        return :ok unless factors.present?

        return :has_legacy_plan if factors[:has_legacy_plan]
        return :not_billable unless factors[:billable]
        return :has_trial if factors[:has_trial]
        return :copilot_enabled if factors[:copilot_enabled]
        return :copilot_disabled_by_parent if factors[:copilot_disabled_by_parent]
        return :owned_by_parent if factors[:owned_by_parent]
        return :no_trade_screening_record unless factors[:has_trade_screen]

        :ok
      end

      sig { params(orgs: T::Array[::Organization], bizs: T::Array[::Business]).returns(EligibilityObj) }
      def get_eligibilities(orgs, bizs)
        eligibilities = {
          organizations: {},
          businesses: {}
        }

        orgs.each { |org| eligibilities[:organizations][org.display_login] = org_eligibility(org) }
        bizs.each { |biz| eligibilities[:businesses][biz.slug] = biz_eligibility(biz, eligibilities) }

        eligibilities
      end

      sig { params(org: ::Organization).returns(EligibilityFactor) }
      def org_eligibility(org)
        eligibility = build_eligibility_factor

        copilot_org = Copilot::Organization.new(org)
        copilot_biz = org.business.present? ? Copilot::Business.new(T.must(org.business)) : nil

        eligibility[:has_trial] = copilot_org.has_trial?
        # an org on e.g a free plan can have a trial, or one on a non-metered teams plan
        eligibility[:billable] = copilot_org.copilot_billable? ||
          eligibility[:has_trial] ||
          !!copilot_org.organization_object.has_valid_payment_method?
        eligibility[:copilot_enabled] = copilot_org.copilot_enabled?
        eligibility[:copilot_disabled_by_parent] = !!(
          copilot_biz &&
          (copilot_disabled_for_org?(copilot_org: copilot_org, copilot_biz: copilot_biz) || copilot_biz.copilot_disabled?)
        )
        eligibility[:billed_through_parent] = org.is_organization_billed_through_business?
        eligibility[:has_legacy_plan] = org.plan.legacy?
        eligibility[:has_trade_screen] = !!org.has_linked_trade_screening_record?
        eligibility[:owned_by_parent] = org.business.present?

        eligibility
      end

      sig { params(copilot_org: Copilot::Organization, copilot_biz: Copilot::Business).returns(T::Boolean) }
      def copilot_disabled_for_org?(copilot_org:, copilot_biz:)
        # When mixed licenses is not enabled, we know that the parent business has disabled Copilot
        # for this org if Copilot isnt enabled and the parent has Copilot enabled for selected organizations.
        # Implicitly, this org cannot be among those enabled.
        base_case = copilot_org.copilot_disabled? && copilot_biz.copilot_enabled_for_selected_organizations?

        return base_case unless copilot_biz.feature_enabled?(:copilot_mixed_licenses)

        # If a business never enabled access, the org's copilot plan would be unconfigured, meaning
        # the org should have the opportunity to enable Copilot for themselves.
        # If a plan was configured, but copilot is disabled on the org, we know the enterprise has specifically
        # denied them access.
        # I believe that when this feature is enabled more generally, enterprise admins will have to opt org
        # in to copilot on their settings page, but as new orgs are added, they should be able to admin themselves.
        base_case && !copilot_org.copilot_plan_unconfigured?
      end

      sig { params(biz: ::Business, eligibilities: EligibilityObj).returns(EligibilityFactor) }
      def biz_eligibility(biz, eligibilities)
        eligibility = build_eligibility_factor

        # Enterprises cannot have a direct trial, but their orgs can.
        # So we need to check all orgs for potential trials.
        # We already have our snazzy lookup created above, so let's use it.
        biz_orgs = biz.organizations.map(&:display_login)

        has_trial = if biz_orgs.empty?
          false
        else
          Copilot::Business.new(biz).all_orgs_have_active_trial?
        end

        copilot_biz = Copilot::Business.new(biz)

        eligibility[:billable] = copilot_biz.copilot_billable?
        eligibility[:copilot_enabled] = copilot_biz.copilot_enabled?
        eligibility[:has_trial] = has_trial
        eligibility[:has_legacy_plan] = biz.plan.legacy?
        eligibility[:has_trade_screen] = true

        eligibility
      end

      sig { returns(EligibilityFactor) }
      def build_eligibility_factor
        T.let({
          billable: false,
          billed_through_parent: false,
          copilot_disabled_by_parent: false,
          copilot_enabled: false,
          has_legacy_plan: false,
          has_trial: false,
          has_trade_screen: false,
          owned_by_parent: false,
        }, EligibilityFactor)
      end
    end
  end
end
