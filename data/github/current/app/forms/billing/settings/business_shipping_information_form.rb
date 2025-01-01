# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    class BusinessShippingInformationForm < ApplicationForm
      include GitHub::Memoizer

      USA = "US"
      CANADA = "CA"

      form do |shipping_information_form|
        T.bind(self, BusinessShippingInformationForm)

        shipping_information_form.text_field(
          name: :entity_name,
          label: "Business/Institution name",
          required: true,
          maxlength: 800
        )

        shipping_information_form.text_field(
          name: :address1,
          label: "Address (P.O. box, company name, c/o)",
          required: true,
          maxlength: 128,
          autocomplete: "address-line1"
        )

        shipping_information_form.text_field(
          name: :address2,
          label: "Address line 2 (Apartment, suite, unit)",
          required: false,
          maxlength: 128,
          autocomplete: "address-line2"
        )

        shipping_information_form.group(layout: :horizontal) do |city_postcode_group|
          city_postcode_group.text_field(
            name: :city,
            label: "City",
            required: true,
            maxlength: 64,
            autocomplete: "address-level2"
          )

          city_postcode_group.text_field(
            name: :postal_code,
            label: "Postal/ZIP code",
            required: postal_code_required?,
            maxlength: 32,
            autocomplete: "postal-code",
            caption: "Required for certain countries"
          )
        end

        shipping_information_form.group(layout: :horizontal) do |country_region_group|
          country_region_group.select_list(
            name: :country_code,
            label: "Country/Region",
            required: true,
            autocomplete: "address-level1",
            prompt: "Choose your country",
            data: { action: "change:billing-country-and-region-selection#handleCountrySelection" }
          ) do |country_select|
            ::TradeControls::Countries.currently_unsanctioned.each do |(country_name, country_alpha2, _)|
              country_select.option(
                label: country_name,
                value: country_alpha2,
                selected: country_selected?(T.must(country_alpha2)),
                **country_attributes_for(T.must(country_alpha2))
              )
            end
          end

          country_region_group.multi(
            name: :region,
            label: "State/Province",
            caption: "Required for certain countries",
            data: { target: "billing-country-and-region-selection.regionSelectionContainer" },
          ) do |state_province_multi|
            state_province_multi.select_list(
              name: :us_states,
              autocomplete: "address-level1",
              prompt: "Select state",
              hidden: shipping_contact.country_code != USA
            ) do |us_state_select|
              StatesAndProvinceHelper::US_STATES.each do |state|
                us_state_select.option(
                  label: state[0],
                  value: state[0],
                  selected: region_selected?(T.must(state[0]))
                )
              end
            end

            state_province_multi.select_list(
              name: :ca_provinces,
              autocomplete: "address-level1",
              prompt: "Select province",
              disabled: true,
              hidden: shipping_contact.country_code != CANADA
            ) do |province_select|
              StatesAndProvinceHelper::CANADA_PROVINCE.each do |province|
                province_select.option(
                  label: province,
                  value: province,
                  selected: region_selected?(province)
                )
              end
            end

            state_province_multi.text_field(
              name: "billing_contact[region]",
              autocomplete: "address-level1",
              data: { target: "billing-country-and-region-selection.defaultRegionSelect" },
              hidden: hide_region_text_field?
            )
          end
        end

        shipping_information_form.group(layout: :horizontal) do |button_group|
          button_group.submit(
            name: :submit,
            label: "Save",
            scheme: :primary
          )

          if shipping_contact.persisted?
            button_group.button(
              name: :cancel,
              type: :button,
              label: "Cancel",
              hidden: !cancellable,
              data: { action: "click:business-shipping-information#cancelShippingInformationEdit" }
            )
          end
        end
      end

      sig { returns(Business) }
      attr_reader :business

      sig { returns(T::Boolean) }
      attr_reader :cancellable

      sig { params(business: Business, cancellable: T::Boolean).void }
      def initialize(business:, cancellable: true)
        @business = business
        @cancellable = cancellable
      end

      private

      sig { returns(Billing::Contact) }
      memoize def shipping_contact
        business.shipping_contact
      end

      sig { returns(T::Boolean) }
      memoize def postal_code_required?
        business.postal_code_required_geo?
      end

      sig { params(country_code: String).returns(T::Boolean) }
      def country_selected?(country_code)
        shipping_contact.country_code == country_code
      end

      sig { params(region: String).returns(T::Boolean) }
      def region_selected?(region)
        shipping_contact.region == region
      end

      sig { returns(T::Boolean) }
      def hide_region_text_field?
        shipping_contact.country_code == USA || shipping_contact.country_code == CANADA
      end

      sig { params(country_code: String).returns(T::Hash[Symbol, T::Hash[Symbol, String]]) }
      def country_attributes_for(country_code)
        case country_code
        when USA
          { "data-region-select-element-name" => "us_states" }
        when CANADA
          { "data-region-select-element-name" => "ca_provinces" }
        else
          {}
        end
      end
    end
  end
end
