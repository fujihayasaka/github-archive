# typed: strict
# frozen_string_literal: true

# Public: Transfer org sponsorships to enterprise account
#
# N.B. This class does not deactivate or otherwise clean up existing org-billed Sponsors subscription items. Callers
# should handle that cleanup externally.
#
# Schedules future activations for enterprise-billed recurring subscription items to ensure the activation aligns
# with the service end dates for the org-billed recurring subscription items.
module Sponsors
  class TransferOrgSponsorshipsToEnterprise
    extend T::Sig
    include GitHub::Memoizer

    sig { params(organization: Organization, actor: User, bill_on: T.nilable(Date)).void }
    def self.call(organization:, actor:, bill_on:)
      new(organization: organization, actor: actor, bill_on: bill_on).call
    end

    sig { params(organization: Organization, actor: User, bill_on: T.nilable(Date)).void }
    def initialize(organization:, actor:, bill_on:)
      @organization = organization
      @actor = actor
      @bill_on = bill_on
    end

    sig { void }
    def call
      return unless GitHub.sponsors_enabled?
      return unless valid_organization?

      organization.grant_sponsorships_access(actor: actor)
      transfer_sponsorships
    end

    private

    sig { returns Organization }
    attr_reader :organization

    sig { returns User }
    attr_reader :actor

    sig { returns T.nilable(Date) }
    attr_reader :bill_on

    sig { void }
    def transfer_sponsorships
      sponsorships_to_migrate.each do |sponsorship|
        tier = sponsorship.tier
        next unless tier
        begin
          Sponsors::UpdateSponsorshipTier.call(
            sponsorship,
            new_tier: tier,
            viewer: actor,
            active_on: bill_on
          )
        rescue Sponsors::UpdateSponsorship::UnprocessableError,
               Sponsors::UpdateSponsorship::ForbiddenError => e
          report_transfer_error(sponsorship: sponsorship, error: e)
        end
      end

      instrument_sponsorship_transfer
    end

    sig { returns T::Boolean }
    def valid_organization?
      invalid_reason = if !sponsorships_to_migrate.present?
        "no sponsorships"
      elsif organization.sponsors_invoiced?
        "sponsors-invoiced"
      elsif bill_on.present? && !GitHub::Billing.future?(T.must(bill_on))
        "no future billing date for org"
      elsif !business&.self_serve_payment?
        "no self serve payment for enterprise"
      end

      return true unless invalid_reason.present?

      log_invalid_organization(reason: invalid_reason)
      false
    end

    sig { returns T.nilable(Business) }
    def business
      organization.business
    end

    sig { returns(T::Array[Sponsorship]) }
    memoize def sponsorships_to_migrate
      sponsorships = organization.sponsorships_as_sponsor.includes(:tier).active.recurring.github
      GitHub::PrefillAssociations.prefill_associations(sponsorships, [:plan_subscription, :subscription_item])
      sponsorships.to_a.select do |sponsorship|
        invalid_plan_sub = sponsorship.plan_subscription != business&.sponsors_plan_subscription
        active_sub_item = T.must(sponsorship.subscription_item).active?
        active_sub_item && invalid_plan_sub
      end
    end

    sig { params(sponsorship: Sponsorship, error: StandardError).void }
    def report_transfer_error(sponsorship:, error:)
      details = {
        "gh.catalog_service": "github/github_sponsors",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.business.id": organization.business&.id,
        "gh.sponsorship.id": sponsorship.id,
      }
      Failbot.report(error)
      GitHub.logger.error(error.message, **details)
    end

    sig { params(reason: String).void }
    def log_invalid_organization(reason:)
      details = {
        "gh.catalog_service": "github/github_sponsors",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.business.id": organization.business&.id || "nil",
        "gh.organization.id": organization.id,
        "org_invalid_reason": reason,
      }
      GitHub.logger.info("Invalid organization for enterprise sponsorship transfer", **details)
    end

    sig { void }
    def instrument_sponsorship_transfer
      GitHub.dogstats.increment("sponsors.transfer_org_sponsorships_to_enterprise.count")

      details = {
        "gh.catalog_service": "github/github_sponsors",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.business.id": organization.business&.id,
        "gh.organization.id": organization.id,
      }
      GitHub.logger.info("Sponsorships transferred from org to enterprise", **details)
    end
  end
end
