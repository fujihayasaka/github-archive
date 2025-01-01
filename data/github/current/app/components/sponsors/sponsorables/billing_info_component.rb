# typed: strict
# frozen_string_literal: true

module Sponsors
  module Sponsorables
    class BillingInfoComponent < ApplicationComponent
      include AvatarHelper

      RETURN_ROUTES = T.let(%i(sponsorships bulk_sponsorships).freeze, T::Array[Symbol])
      DEFAULT_RETURN_ROUTE = :sponsorships

      sig do
        params(
          sponsor: GitHubSponsors::Types::Sponsor,
          sponsorable: T.nilable(GitHubSponsors::Types::Sponsorable),
          selected_tier: T.nilable(SponsorsTier),
          sponsorship: T.nilable(Sponsorship),
          privacy_level: T.nilable(String),
          email_opt_in: T.nilable(T::Boolean),
          return_route: T.nilable(Symbol)
        ).void
      end
      def initialize(sponsor:,
                     sponsorable: nil,
                     selected_tier: nil,
                     sponsorship: nil,
                     privacy_level: nil,
                     email_opt_in: nil,
                     return_route: DEFAULT_RETURN_ROUTE)
        @sponsorable = sponsorable
        @sponsor = sponsor
        @selected_tier = selected_tier
        @sponsorship = sponsorship
        @privacy_level = privacy_level
        @email_opt_in = email_opt_in
        @return_route = T.let(fetch_or_fallback(RETURN_ROUTES, return_route, DEFAULT_RETURN_ROUTE), Symbol)
      end

      private

      sig { returns(GitHubSponsors::Types::Sponsor) }
      attr_reader :sponsor
      sig { returns(T.nilable(GitHubSponsors::Types::Sponsorable)) }
      attr_reader :sponsorable
      sig { returns(Symbol) }
      attr_reader :return_route

      delegate :payment_method, :sponsors_plan_duration, :trade_screening_record, to: :sponsor

      sig { returns(T::Boolean) }
      def render?
        return false unless GitHub.sponsors_enabled?
        return false unless logged_in? && sponsor.present?

        if return_route == :sponsorships
          return false unless sponsorable.present? && @selected_tier.present?
        end

        true
      end

      sig { returns(T::Boolean) }
      def can_edit_trade_screening_info?
        return false if sponsor.sponsors_invoiced?
        return false if sponsor.organization? && sponsor.business.present?
        return false if data_collection_linking_enabled?

        sponsor.is_allowed_to_edit_trade_screening_information?
      end

      sig { returns(T::Boolean) }
      memoize def valid_payment_method?
        !sponsor.has_lic_r_stopgap_restriction? && sponsor.has_valid_payment_method_for_sponsorships?
      end

      sig { returns(T.nilable(String)) }
      memoize def return_url
        case return_route
        when :sponsorships
          sponsorable_sponsorships_path(sponsorable, return_url_params)
        when :bulk_sponsorships
          sponsors_bulk_sponsorship_frequencies_path(return_url_params)
        end
      end

      sig { returns(T::Hash[Symbol, T.any(String, Integer)]) }
      def return_url_params
        params = { sponsor: sponsor.display_login }
        if return_route == :sponsorships
          if @selected_tier&.persisted?
            params[:tier_id] = @selected_tier.id
          else
            params[:amount] = @selected_tier&.monthly_price_in_dollars&.to_i
            params[:frequency] = @selected_tier&.one_time? ? "one-time" : "recurring"
          end
          params[:privacy_level] = @privacy_level
          params[:email_opt_in] = @email_opt_in ? "on" : "off"
        end
        params
      end

      sig { returns(String) }
      def account_type
        if sponsor.organization?
          "Organization"
        else
          "Personal"
        end
      end

      sig { returns(String) }
      def payment_flow_loaded_from
        if sponsorable
          "SPONSORSHIPS"
        else
          "BULK_SPONSORSHIP"
        end
      end

      sig { returns(T::Boolean) }
      def hide_name_address_collection_wrapper?
        valid_payment_method? || has_saved_trade_screening_record?
      end

      sig { returns(T::Boolean) }
      memoize def data_collection_linking_enabled?
        sponsor.org_is_on_standard_tos?
      end

      sig { returns(T::Boolean) }
      memoize def collect_billing_info?
        !valid_payment_method? && !has_saved_trade_screening_record?
      end

      sig { returns(T::Boolean) }
      memoize def show_data_collection_component?
        !valid_payment_method? || has_saved_trade_screening_record?
      end

      sig { returns(T::Boolean) }
      memoize def show_payment_method_top_bar?
        return true unless data_collection_linking_enabled?
        # we currently don't show the data collection component if the user has a valid payment method stored
        # with no screening record. In that case, we just show the account name/avatar
        return true if valid_payment_method? && !has_saved_trade_screening_record?

        show_data_collection_component?
      end

      sig { returns(T::Boolean) }
      def org_has_no_linked_info_but_user_has_saved_info?
        return false if sponsor.has_linked_trade_screening_record?

        current_user.has_saved_trade_screening_record?
      end

      sig { returns(T::Boolean) }
      memoize def has_saved_trade_screening_record?
        sponsor.has_saved_trade_screening_record?
      end

      sig { returns(T.nilable(Sponsors::InvoicedCustomerBillingAddress)) }
      memoize def billing_address
        if billing_contact
          Sponsors::InvoicedCustomerBillingAddress.new(billing_contact)
        end
      end

      # Private: The Zuora customer whose information is listed as the invoiced customer's billing contact
      #
      # Returns a Sponsors::BillingContactResult
      sig { returns(T.nilable(Sponsors::BillingContactResult)) }
      def billing_contact
        return unless sponsor.sponsors_invoiced?
        sponsor.sponsors_billing_contact
      end
    end
  end
end
