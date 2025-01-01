# typed: strict
# frozen_string_literal: true

module Orgs
  module Sponsorings
    class InvoicedBillingAccountForm < ApplicationForm
      include GitHub::Memoizer

      USA = "US"
      CANADA = "CA"

      form do |invoiced_billing_form|
        T.bind(self, InvoicedBillingAccountForm)

        invoiced_billing_form.text_field(
          name: "account[name]",
          label: "Sponsor name",
          value: creator&.name || billing_contact.entity_name,
          required: true,
          validation_message: validation_message_for(:name),
        )

        invoiced_billing_form.text_field(
          name: "account[address][line1]",
          label: "Address (P.O. box, company name, c/o)",
          maxlength: 128,
          autocomplete: "address-line1",
          value: creator&.address&.line1 || billing_contact.address1,
          required: true,
          validation_message: validation_message_for(:address_line1),
        )

        invoiced_billing_form.text_field(
          name: "account[address][line2]",
          label: "Address line 2 (Apartment, suite, unit)",
          maxlength: 128,
          autocomplete: "address-line2",
          value: creator&.address&.line2 || billing_contact.address2,
          required: false,
          validation_message: validation_message_for(:address_line2),
        )

        invoiced_billing_form.group(layout: :horizontal) do |city_postcode_group|
          city_postcode_group.text_field(
            name: "account[address][city]",
            label: "City",
            autocomplete: "address-level2",
            value: creator&.address&.city || billing_contact.city,
            required: true,
            validation_message: validation_message_for(:address_city),
          )

          city_postcode_group.text_field(
            name: "account[address][postal_code]",
            label: "Postal/ZIP code",
            autocomplete: "postal-code",
            caption: "Required for certain countries",
            value: creator&.address&.postal_code || billing_contact.postal_code,
            required: postal_code_required?,
            validation_message: validation_message_for(:postal_code),
          )
        end

        invoiced_billing_form.group(layout: :horizontal) do |country_region_group|
          country_region_group.select_list(
            name: "account[address][country]",
            label: "Country/Region",
            autocomplete: "address-level1",
            prompt: "Choose your country",
            data: { action: "change:country-and-region-selection#handleCountrySelection" },
            required: true,
            validation_message: validation_message_for(:address_country),
          ) do |country_select|
            ::TradeControls::Countries.currently_unsanctioned.each do |(country_name, country_alpha2, _)|
              country_select.option(
                label: country_name,
                value: country_alpha2,
                selected: country_selected?(T.must(country_alpha2)),
                **country_attributes_for(T.must(country_alpha2)),
              )
            end
          end

          country_region_group.multi(
            name: "account[address][state]",
            label: "State/Province",
            caption: "Required for certain countries",
            data: { target: "country-and-region-selection.regionSelectionContainer" },
            validation_message: validation_message_for(:address_state),
          ) do |state_province_multi|
            state_province_multi.select_list(
              name: :us_states,
              autocomplete: "address-level1",
              prompt: "Select state",
              hidden: (creator&.address&.country || billing_contact.country_code) != USA,
              validation_message: validation_message_for(:address_state),
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
              disabled: true,
              autocomplete: "address-level1",
              prompt: "Select province",
              hidden: billing_contact.country_code != CANADA,
              validation_message: validation_message_for(:address_state),
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
              name: "account[address][state]",
              value: billing_contact.region,
              autocomplete: "address-level1",
              data: { target: "country-and-region-selection.defaultRegionSelect" },
              hidden: hide_state_text_field?,
              validation_message: validation_message_for(:address_state),
            )
          end
        end

        invoiced_billing_form.text_field(
          name: "account[email]",
          label: "Billing email",
          value: creator&.email || organization.billing_email,
          required: true,
          validation_message: validation_message_for(:email),
        )

        invoiced_billing_form.submit(
          name: :submit,
          label: "Submit",
          scheme: :primary,
          align_self: :end,
        )
      end

      sig { returns(Organization) }
      attr_reader :organization

      sig { returns(T.nilable(Sponsors::InvoicedSponsorAccountCreator)) }
      attr_reader :creator

      sig { returns(T.nilable(User)) }
      attr_reader :current_user

      sig do
        params(
          organization: Organization,
          creator: T.nilable(Sponsors::InvoicedSponsorAccountCreator),
          current_user: T.nilable(User),
        ).void
      end
      def initialize(organization:, creator: nil, current_user: nil)
        @organization  = organization
        @creator       = creator
        @current_user  = current_user
      end

      sig { params(country_code: String).returns(T::Boolean) }
      def country_selected?(country_code)
        (creator&.address&.country || billing_contact.country_code) == country_code
      end

      sig { params(region: String).returns(T::Boolean) }
      def region_selected?(region)
        (creator&.address&.state || billing_contact.region) == region
      end

      sig { returns(T::Boolean) }
      def hide_state_text_field?
        country_code = creator&.address&.country || billing_contact.country_code
        country_code == USA || country_code == CANADA
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

      sig { returns(T::Boolean) }
      memoize def postal_code_required?
        organization.postal_code_required_geo?
      end

      sig { returns(T.any(Billing::Contact, AccountScreeningProfile)) }
      memoize def billing_contact
        organization.billing_contact
      end

      sig { params(attribute: Symbol).returns(T.nilable(String)) }
      def validation_message_for(attribute)
        return unless customer_creator = creator
        return unless messages = customer_creator.errors.full_messages_for(attribute)
        return unless messages.any?
        messages.to_sentence
      end
    end
  end
end
