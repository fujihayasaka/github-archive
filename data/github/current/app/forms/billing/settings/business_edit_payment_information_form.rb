# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    class BusinessEditPaymentInformationForm < ApplicationForm
      include GitHub::Memoizer

      USA = "US"
      CANADA = "CA"

      form do |bus_pay_info_form|
        T.bind(self, BusinessEditPaymentInformationForm)

        bus_pay_info_form.hidden(
          name: :return_to,
          value: return_to,
          id: nil,
          scope_name_to_model: false,
          scope_id_to_model: false
        )

        bus_pay_info_form.hidden(
          name: :target,
          value: "business",
          scope_name_to_model: false
        )
        bus_pay_info_form.hidden(
          name: "business_id",
          value: business.slug,
          scope_name_to_model: false
        )

        bus_pay_info_form.hidden(
          name: :form_loaded_from,
          id: "form-loaded-from",
          value: "BUSINESS",
          scope_name_to_model: false
        )

        bus_pay_info_form.text_field(
          name: :entity_name,
          label: "Business/Institution name",
          required: true,
          **business.account_screening_profile_update_result.primer_form_attributes_for(:entity_name)
        )

        bus_pay_info_form.text_field(
          name: :address1,
          label: "Address (P.O. box, company name, c/o)",
          required: true,
          maxlength: 128,
          autocomplete: "address-line1",
          **business.account_screening_profile_update_result.primer_form_attributes_for(:address1)
        )

        bus_pay_info_form.text_field(
          name: :address2,
          label: "Address line 2 (Apartment, suite, unit)",
          required: false,
          maxlength: 128,
          autocomplete: "address-line2",
          **business.account_screening_profile_update_result.primer_form_attributes_for(:address2)
        )

        bus_pay_info_form.group(layout: :horizontal) do |city_postcode_group|
          city_postcode_group.text_field(
            name: :city,
            label: "City",
            required: true,
            autocomplete: "address-level2",
            **business.account_screening_profile_update_result.primer_form_attributes_for(:city)
          )

          city_postcode_group.text_field(
            name: :postal_code,
            label: "Postal/Zip code",
            required: postal_code_required?,
            autocomplete: "postal-code",
            caption: "Required for certain countries",
            **business.account_screening_profile_update_result.primer_form_attributes_for(:postal_code)
          )
        end

        bus_pay_info_form.group(layout: :horizontal) do |country_region_group|
          country_region_group.select_list(
            name: :country_code,
            label: "Country/Region",
            classes: "select-country js-name-address-select-country",
            autocomplete: "address-level1",
            prompt: "Choose your country",
            required: true,
            **business.account_screening_profile_update_result.primer_form_attributes_for(:country_code)
          ) do |country_select|
            countries.each do |(country_name, country_alpha2, _)|
              country_select.option(
                label: country_name,
                value: country_alpha2,
                selected: country_of_profile?(country_alpha2)
              )
            end
          end

          country_region_group.multi(name: :region, label: "State/Province", caption: "Required for certain countries") do |state_province_multi|
            state_province_multi.select_list(
              name: :us_states,
              classes: "select-state js-select-state",
              autocomplete: "address-level1",
              prompt: "Select state",
              hidden: profile&.country_code != USA
            ) do |us_state_select|
              us_states.each do |state|
                us_state_select.option(
                  label: state[0],
                  value: state[0],
                  selected: region_of_profile?(state[0])
                )
              end
            end

            state_province_multi.select_list(
              name: :ca_provinces,
              disabled: true,
              autocomplete: "address-level1",
              prompt: "Select province",
              hidden: profile&.country_code != CANADA
            ) do |province_select|
              canada_provinces.each do |province|
                province_select.option(
                  label: province,
                  value: province,
                  selected: region_of_profile?(province)
                )
              end
            end

            state_province_multi.text_field(
              name: :region,
              value: profile&.region,
              disabled: true,
              autocomplete: "address-level1",
              hidden: profile&.country_code == USA || profile&.country_code == CANADA
            )
          end
        end

        bus_pay_info_form.text_field(
          name: :vat_code,
          label: "VAT/GST ID",
          required: vat_code_required?,
          **business.account_screening_profile_update_result.primer_form_attributes_for(:vat_code)
        )

        bus_pay_info_form.group(layout: :horizontal) do |button_group|
          button_group.submit(
            name: :submit,
            label: "Save",
            scheme: :primary,
            id: "submit_personal_profile"
          )

          if !show_form
            button_group.button(
              name: :reset,
              type: :reset,
              value: "Cancel",
              label: "Cancel",
              class: "js-billing-settings-billing-information-cancel-button"
            )
          end
        end
      end

      attr_reader :business, :return_to, :show_form

      def initialize(business:, return_to: nil, show_form: false)
        @business = business
        @return_to = return_to
        @show_form = show_form
      end

      def country_of_profile?(country_code)
        profile&.country_code == country_code || business.account_screening_profile_update_result.field_value("country_code") == country_code
      end

      def region_of_profile?(state)
        profile&.region == state || business.account_screening_profile_update_result.field_value("region") == state
      end

      def us_states
        StatesAndProvinceHelper::US_STATES
      end

      def canada_provinces
        StatesAndProvinceHelper::CANADA_PROVINCE
      end

      def countries
        ::TradeControls::Countries.currently_unsanctioned
      end

      def trial?
        business.trial?
      end

      memoize def vat_code_required?
        business.vat_code_required_geo?
      end

      memoize def postal_code_required?
        business.postal_code_required_geo?
      end

      memoize def profile
        business.trade_screening_record
      end
    end
  end
end
