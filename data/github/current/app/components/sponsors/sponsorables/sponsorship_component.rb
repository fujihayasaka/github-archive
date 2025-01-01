# typed: strict
# frozen_string_literal: true

module Sponsors
  module Sponsorables
    class SponsorshipComponent < ApplicationComponent
      extend T::Sig

      REPO_MEMBERSHIP_MESSAGE = "Reminder, some rewards like access to private repositories will allow other " \
        "repository members to see your membership."

      # sponsorable - the maintainer who should be paid; required if `bulk_sponsorship_rows` is empty
      # selected_tier - the tier belonging to the maintainer representing how much the sponsor wants to pay; required
      #                 if `bulk_sponsorship_rows` is empty
      # sponsor - the account who will pay the maintainer
      # sponsorship - the existing sponsorship from `sponsor` to `sponsorable`, if one exists
      # privacy_level - whether the identity of the sponsor should be public knowledge; choose "public" or "private"
      # opted_in_to_email - whether the sponsor would like to receive email updates from the sponsorable
      # pay_prorated - whether the sponsor should pay a prorated amount for the `selected_tier` today versus the full
      #                tier cost
      # sponsorable_metadata - optional user-given metadata for the sponsorship, data the sponsorable may
      #                        have specified
      # parent_tier - optional tier that's the closest lesser-value tier of the same frequency as
      #               `selected_tier`; only applicable if `selected_tier` is a custom tier
      # bulk_sponsorship_rows - rows of bulk sponsorship data for the individual sponsorships to be made; required if
      #                         `sponsorable` and `selected_tier` are blank
      sig do
        params(
          sponsorable: T.nilable(GitHubSponsors::Types::Sponsorable),
          selected_tier: T.nilable(SponsorsTier),
          sponsor: T.nilable(GitHubSponsors::Types::Sponsor),
          sponsorship: T.nilable(Sponsorship),
          privacy_level: T.any(String, Symbol),
          opted_in_to_email: T::Boolean,
          pay_prorated: T::Boolean,
          sponsorable_metadata: T.nilable(T::Hash[T.any(String, Symbol), T.untyped]),
          parent_tier: T.nilable(SponsorsTier),
          active_on: T.nilable(T.any(Date, DateTime, ActiveSupport::TimeWithZone)),
          bulk_sponsorship_rows: T.nilable(T::Array[Sponsors::BulkSponsorshipRow])
        ).void
      end
      def initialize(sponsorable: nil,
                     selected_tier: nil,
                     sponsor: nil,
                     sponsorship: nil,
                     privacy_level: "public",
                     opted_in_to_email: true,
                     pay_prorated: true,
                     sponsorable_metadata: nil,
                     parent_tier: nil,
                     active_on: nil,
                     bulk_sponsorship_rows: [])
        @sponsorable = sponsorable
        @sponsor = sponsor
        @sponsors_business_tax_identifier = T.let(
          @sponsor&.newest_sponsors_business_tax_identifier,
          T.nilable(SponsorsBusinessTaxIdentifier)
        )
        @sponsorship = sponsorship
        @selected_tier = selected_tier
        @current_tier = T.let(@sponsorship&.tier, T.nilable(SponsorsTier))
        @privacy_level = privacy_level
        @opted_in_to_email = opted_in_to_email
        @pay_prorated = pay_prorated
        @sponsorable_metadata = T.let(
          sponsorable_metadata || {},
          T::Hash[T.any(String, Symbol), T.untyped]
        )
        @parent_tier = parent_tier
        @active_on = active_on
        @bulk_sponsorship_rows = T.let(bulk_sponsorship_rows || [], T::Array[Sponsors::BulkSponsorshipRow])
      end

      private

      sig { returns T.nilable(GitHubSponsors::Types::Sponsorable) }
      attr_reader :sponsorable

      sig { returns T.nilable(SponsorsBusinessTaxIdentifier) }
      attr_reader :sponsors_business_tax_identifier

      sig { returns GitHubSponsors::Types::Sponsor }
      def sponsor
        @sponsor || current_user
      end

      sig { returns T.nilable(SponsorsTier) }
      attr_reader :parent_tier

      sig { returns T::Boolean }
      def sponsors_invoiced?
        sponsor.sponsors_invoiced?
      end

      sig { returns T::Boolean }
      def render?
        return false if single_sponsorship_without_selected_tier?
        return false if single_sponsorship_without_sponsorable?
        return false unless logged_in? && @sponsor.present?
        return false if @sponsor.has_commercial_interaction_restriction?

        @sponsor.has_valid_payment_method_for_sponsorships?
      end

      sig { returns Symbol }
      def form_method
        if editing?
          :put
        else
          :post
        end
      end

      sig { returns String }
      def form_path
        if bulk_sponsorship?
          sponsors_bulk_sponsorship_checkout_path(confirm: "1", sponsor: sponsor)
        else
          sponsorable_sponsorships_path(sponsorable)
        end
      end

      sig { returns T::Boolean }
      def public?
        @privacy_level == "public"
      end

      sig { returns T::Boolean }
      def private?
        !public?
      end

      sig { returns T.nilable(Organization) }
      memoize def linked_org_for_sponsor
        sponsor.sponsoring_parent_organization if sponsor.organization?
      end

      sig { returns String }
      def privacy_note_summary
        sponsorable_summary = if bulk_sponsorship?
          "the maintainers you're sponsoring"
        elsif T.must(sponsorable).organization?
          "#{sponsorable}'s members"
        else
          sponsorable
        end

        sponsor_summary = if sponsor.organization?
          if linked_org_for_sponsor
            ", #{linked_org_for_sponsor}'s members, and #{sponsor}'s members"
          else
            " and #{sponsor}'s members"
          end
        end

        sponsor_descriptor = if sponsor == current_user
          "you are"
        elsif linked_org_for_sponsor
          "#{linked_org_for_sponsor} is"
        else
          "#{sponsor} is"
        end

        "Only #{sponsorable_summary}#{sponsor_summary} will be able to see that #{sponsor_descriptor} a sponsor."
      end

      sig { returns String }
      def email_updates_note_subject
        if bulk_sponsorship?
          "the maintainers you're sponsoring"
        else
          T.must(sponsorable).display_login
        end
      end

      sig { returns String }
      def privacy_note_subject
        if bulk_sponsorship?
          "all the maintainers you're sponsoring"
        else
          "that you sponsor #{sponsorable}"
        end
      end

      sig { returns T.nilable(String) }
      memoize def dollar_amount_privacy_note
        return unless sponsor.organization?

        if linked_org_for_sponsor
          "Neither #{linked_org_for_sponsor}'s members nor #{sponsor}'s members will be able to see the amount."
        else
          "#{sponsor}'s members will not be able to see the amount."
        end
      end

      sig { returns T.nilable(T::Boolean) }
      def show_repo_membership_message?
        return false if bulk_sponsorship?

        selected_tier = T.must_because(@selected_tier) { "#render? ensures non-nil when not bulk sponsoring" }

        if selected_tier.custom? && selected_tier.new_record?
          # Unsaved custom tiers are given at sponsorship checkout time along with the closest lower value tier
          # already calculated, if any exists, so use that to avoid a database query:
          parent_tier&.grants_repository_access_to?(sponsor)
        else
          selected_tier.grants_repository_access_to?(sponsor)
        end
      end

      sig { returns Billing::Money }
      memoize def payment_amount
        if bulk_sponsorship?
          @bulk_sponsorship_rows.inject(Billing::Money.zero) { |sum, row| sum + row.amount }
        else
          T.must(@selected_tier).price(sponsor: sponsor, sponsorship: @sponsorship, prorated: @pay_prorated)
        end
      end

      sig { returns T.any(Integer, BigDecimal) }
      def monthly_price_in_dollars
        if bulk_sponsorship?
          payment_amount.dollars
        else
          T.must(@selected_tier).monthly_price_in_dollars
        end
      end

      sig { returns String }
      def submit_text
        if bulk_sponsorship?
          "Sponsor #{@bulk_sponsorship_rows.size} maintainers"
        elsif editing?
          "Update sponsorship"
        else
          "Sponsor #{T.must(sponsorable).display_login}"
        end
      end

      sig { returns String }
      def disable_with_text
        if bulk_sponsorship?
          "Updating sponsorships"
        elsif editing?
          "Updating sponsorship"
        else
          "Sponsoring #{T.must(sponsorable).display_login}"
        end
      end

      sig { returns String }
      def subscription_duration
        sponsor.sponsors_plan_duration.downcase
      end

      sig { returns Date }
      memoize def default_end_date
        GitHub::Billing.today + 1.month
      end

      sig { returns Integer }
      memoize def default_end_month
        default_end_date.month
      end

      sig { returns Integer }
      def default_end_year
        default_end_date.year
      end

      sig { returns T.nilable(ActiveSupport::TimeWithZone) }
      def sponsorship_expiration_date
        @sponsorship&.expires_at
      end

      sig { returns Integer }
      def end_month
        sponsorship_expiration_date&.month || default_end_month
      end

      sig { returns Integer }
      def end_year
        sponsorship_expiration_date&.year || default_end_year
      end

      sig { returns Integer }
      def max_invoice_end_year
        default_end_year + 5
      end

      sig { returns T::Boolean }
      def editing?
        return false if bulk_sponsorship?
        return false unless @current_tier.present?

        @current_tier.recurring? && T.must(@selected_tier).recurring?
      end

      sig { returns T::Boolean }
      def can_cancel?
        return false if bulk_sponsorship?
        return false unless @current_tier&.recurring?
        return false if @sponsorship&.has_pending_activation?
        true
      end

      sig { returns T::Boolean }
      def editing_but_unchanged_tier?
        return false unless editing?
        return false unless @selected_tier&.persisted?

        T.must(@current_tier).id == @selected_tier.id
      end

      sig { returns T.nilable(Billing::SubscriptionItem) }
      def current_subscription_item
        return unless @current_tier
        sponsor
          .subscription_items
          .detect { |item| item.subscribable == @current_tier }
      end

      sig { returns T.nilable(String) }
      memoize def next_billing_date
        sponsor.formatted_next_sponsors_billing_date
      end

      sig { returns T::Boolean }
      def concurrent?
        !!@sponsorship&.concurrent_payment?(tier_paid: @selected_tier)
      end

      sig { returns T.nilable(String) }
      def country_code
        sponsors_business_tax_identifier&.country
      end

      sig { returns T::Hash[String, String] }
      def countries
        # These are inverted because Rails wants name -> value and we have value -> name:
        Sponsors::ISO3166.countries.invert
      end

      sig { returns T::Hash[String, String] }
      def regions
        subdivisions = Sponsors::ISO3166.subdivisions(country_code: country_code)
        subdivisions&.invert
      end

      sig { returns T::Boolean }
      def vat_code_hidden?
        SponsorsBusinessTaxIdentifier::COUNTRY_CODES_WITHOUT_VAT_CODES.include?(country_code)
      end

      sig { returns T.nilable(T::Boolean) }
      def one_time_tier?
        if bulk_sponsorship?
          bulk_sponsorship_row = T.must(@bulk_sponsorship_rows.first)
          !bulk_sponsorship_row.recurring? # all rows should have the same frequency
        else
          @selected_tier&.one_time?
        end
      end

      sig { returns T::Boolean }
      def recurring_tier?
        !one_time_tier?
      end

      sig { returns T::Boolean }
      memoize def bulk_sponsorship?
        @bulk_sponsorship_rows.present?
      end

      sig { returns T::Boolean }
      def single_sponsorship_without_selected_tier?
        !bulk_sponsorship? && @selected_tier.blank?
      end

      sig { returns T::Boolean }
      def single_sponsorship_without_sponsorable?
        !bulk_sponsorship? && sponsorable.blank?
      end

      sig { returns T::Boolean }
      def self_serve_enterprise_sponsorship?
        return false unless sponsor.organization?
        return false if sponsors_invoiced?
        return false unless sponsor.business.present?
        return false unless sponsor.business.feature_enabled?(:sponsors_self_serve_enterprise)

        sponsor.business.self_serve_payment?
      end

      sig { returns T::Boolean }
      def show_tax_information?
        return true unless self_serve_enterprise_sponsorship?
        false
      end

      sig { returns String }
      def private_sponsorship_caption
        message = privacy_note_summary
        dollar_amount_privacy_note = self.dollar_amount_privacy_note
        message += " " + dollar_amount_privacy_note if dollar_amount_privacy_note
        message += " " + REPO_MEMBERSHIP_MESSAGE if show_repo_membership_message?

        message
      end
    end
  end
end
