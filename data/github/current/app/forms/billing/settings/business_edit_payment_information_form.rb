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

        bus_pay_info_form.group(layout: :horizontal) do |business_name_vat_group|
          business_name_vat_group.text_field(
            name: :entity_name,
            label: "Business/Institution name",
            required: true,
            **attributes_for(:entity_name)
          )

          business_name_vat_group.text_field(
            name: :vat_code,
            label: "VAT/GST ID",
            required: vat_code_required?,
            **attributes_for(:vat_code)
          )
        end

        bus_pay_info_form.text_field(
          name: :address1,
          label: GitHub::HTMLSafeString.make("Address <span class='text-normal'>(Street, P.O. box)</span>"),
          required: true,
          maxlength: 128,
          autocomplete: "address-line1",
          **attributes_for(:address1)
        )

        bus_pay_info_form.text_field(
          name: :address2,
          label: GitHub::HTMLSafeString.make("Address line 2  <span class='text-normal'>(Apartment, suite, unit)</span>"),
          required: false,
          maxlength: 128,
          autocomplete: "address-line2",
          **attributes_for(:address2)
        )

        bus_pay_info_form.group(layout: :horizontal) do |city_postcode_group|
          city_postcode_group.text_field(
            name: :city,
            label: "City",
            required: true,
            autocomplete: "address-level2",
            **attributes_for(:city)
          )

          city_postcode_group.text_field(
            name: :postal_code,
            label: "Postal/Zip code",
            required: postal_code_required?,
            autocomplete: "postal-code",
            caption: "Required for certain countries",
            **attributes_for(:postal_code)
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
            **attributes_for(:country_code)
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
              hidden: billing_contact.country_code != USA
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
              hidden: billing_contact.country_code != CANADA
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
              value: billing_contact.region,
              disabled: true,
              autocomplete: "address-level1",
              hidden: billing_contact.country_code == USA || billing_contact.country_code == CANADA
            )
          end
        end

        bus_pay_info_form.group(layout: :horizontal) do |button_group|
          button_group.submit(
            name: :submit,
            label: "Save billing information",
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

        # This was moved to the bottom as a temporary workaround since the
        # hidden fields take up space on the form
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
      end

      attr_reader :business, :return_to, :show_form

      def initialize(business:, return_to: nil, show_form: false)
        @business = business
        @return_to = return_to
        @show_form = show_form
      end

      def attributes_for(field_name)
        update_result.primer_form_attributes_for(field_name)
      end

      def field_for(field_name)
        update_result.field_value(field_name)
      end

      def update_result
        @update_result ||= business.contact_information_stash(billing_contact.address_type || "billing")
      end

      def country_of_profile?(country_code)
        billing_contact.country_code == country_code || field_for("country_code") == country_code
      end

      def region_of_profile?(state)
        billing_contact.region == state || field_for("region") == state
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

      memoize def billing_contact
        business.billing_contact
      end
    end
  end
end
