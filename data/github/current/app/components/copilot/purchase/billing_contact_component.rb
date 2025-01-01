# typed: strict
# frozen_string_literal: true

module Copilot
  module Purchase
    class BillingContactComponent < ApplicationComponent

      include GitHub::Memoizer

      sig { returns(T.any(::Organization, ::Business)) }
      attr_reader :selected_account

      sig { returns(T.any(::Billing::Contact, ::AccountScreeningProfile)) }
      attr_reader :billing_contact

      sig { params(selected_account: T.any(::Organization, ::Business)).void }
      def initialize(selected_account:)
        @selected_account = selected_account
        @billing_contact = T.let(get_billing_contact, T.any(::Billing::Contact, ::AccountScreeningProfile))
      end

      sig { returns(T::Boolean) }
      def has_billing_contact_info?
        selected_account.has_saved_trade_screening_record? && (
          billing_contact.address1.present? ||
          billing_contact.address2.present? ||
          billing_contact.city.present? ||
          billing_contact.region.present? ||
          billing_contact.postal_code.present?
        )
      end

      sig { returns(String) }
      memoize def city_region_post_code
        city = billing_contact.city

        return "" unless city.present?

        region = billing_contact.region
        postal_code = billing_contact.postal_code

        return city unless region.present? || postal_code.present?

        region_post_code = [region, postal_code].compact.join(" ")

        "#{city}" + (region_post_code.present? ? ", #{region_post_code}" : "")
      end

      # Copied from AccountScreeningProfile#country
      # We have to do this because the Billing::Contact model does not expose this method.
      sig { returns(T.nilable(String)) }
      memoize def country
        return country_from_code(billing_contact.country_code).name if billing_contact.is_a?(::Billing::Contact)

        T.cast(billing_contact, ::AccountScreeningProfile).country.name
      end

      sig { override.void }
      def before_render
        @user = T.let(current_user, T.nilable(::User))
      end

      sig { returns(::User) }
      def user
        T.must(@user)
      end

      sig { returns(T::Boolean) }
      def org_has_no_linked_info_but_user_has_saved_info?
        return false unless selected_account.organization? && selected_account.org_is_on_standard_tos?
        return false if selected_account.has_linked_trade_screening_record?

        user.has_saved_trade_screening_record?
      end

      private

      sig { params(country_code: T.nilable(String)).returns(TradeControls::Country) }
      def country_from_code(country_code)
        country_info = Braintree::Address::CountryNames.find do |_, alpha2, _, _|
          alpha2 == country_code
        end
        TradeControls::Country.from_braintree(country_info)
      end

      sig { returns(T.any(::Billing::Contact, ::AccountScreeningProfile)) }
      def get_billing_contact
        return selected_account.trade_screening_record if selected_account.trade_screening_record.valid?
        selected_account.billing_contact
      end
    end
  end
end
