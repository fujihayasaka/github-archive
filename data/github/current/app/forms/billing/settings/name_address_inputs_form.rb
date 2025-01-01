# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    class NameAddressInputsForm < ApplicationForm
      USA = "US"
      CANADA = "CA"

      include GitHub::Memoizer

      form do |name_address_form|
        T.bind(self, NameAddressInputsForm)

        if show_user_fields?
          name_address_form.group(layout: :horizontal, test_selector: "individual-name-address-fields") do |name_group|
            name_group.text_field(
              name: :first_name,
              label: "First name",
              required: true,
              maxlength: 64,
              disabled: disable_form_inputs?,
              autocomplete: "given-name",
              **attributes_for(:first_name)
            )

            name_group.text_field(
              name: :middle_name,
              label: "Middle name",
              required: false,
              maxlength: 64,
              disabled: disable_form_inputs?,
              autocomplete: "middle-name",
              **attributes_for(:middle_name)
            ) if show_middle_name?

            name_group.text_field(
              name: :last_name,
              label: "Last name",
              required: true,
              maxlength: 64,
              disabled: disable_form_inputs?,
              autocomplete: "family-name",
              **attributes_for(:last_name)
            )
          end
        end

        if show_org_fields? || show_business_fields?
          name_address_form.group(layout: :horizontal, test_selector: "entity-name-address-fields") do |name_vat_group|
            name_vat_group.text_field(
              name: :entity_name,
              label: "Business/Institution name",
              required: true,
              maxlength: 800,
              disabled: disable_form_inputs?,
              autocomplete: "organization",
              **attributes_for(:entity_name)
            )

            name_vat_group.fields_for(vat_fields_for, contact, nested: false) do |builder|
              Billing::Settings::VatCodeForm.new(
                builder,
                required: vat_code_required?,
                disabled: disable_form_inputs?,
                form_attributes: attributes_for(:vat_code)
              )
            end
          end
        end
        name_address_form.text_field(
          name: :address1,
          label: GitHub::HTMLSafeString.make("Address <span class='text-normal'>(Street, P.O. box)</span>"),
          required: true,
          maxlength: 128,
          disabled: disable_form_inputs?,
          autocomplete: "address-line1",
          **attributes_for(:address1)
        )

        name_address_form.text_field(
          name: :address2,
          label: GitHub::HTMLSafeString.make("Address line 2  <span class='text-normal'>(Apartment, suite, unit)</span>"),
          required: false,
          maxlength: 128,
          disabled: disable_form_inputs?,
          autocomplete: "address-line2",
          **attributes_for(:address2)
        )

        name_address_form.text_field(
          name: :city,
          label: "City",
          required: true,
          maxlength: 64,
          disabled: disable_form_inputs?,
          autocomplete: "address-level2",
          **attributes_for(:city)
        )

        name_address_form.select_list(
          name: :country_code,
          label: "Country/Region",
          disabled: disable_form_inputs,
          classes: "select-country js-name-address-select-country",
          autocomplete: "address-level1",
          prompt: "Choose your country/region",
          required: true,
          **attributes_for(:country_code)
        ) do |country_select|
          countries.each do |(country_name, country_alpha2, _)|
            country_select.option(
              label: country_name,
              value: country_alpha2,
              selected: country_of_contact?(country_alpha2)
            )
          end
        end

        name_address_form.group(layout: :horizontal) do |country_region_group|
          country_region_group.multi(name: :region, label: "State/Province", caption: "Required for certain countries", **attributes_for(:region)) do |state_province_multi|
            state_province_multi.select_list(
              name: :us_states,
              disabled: disable_form_inputs,
              classes: "select-state js-select-state",
              autocomplete: "address-level1",
              prompt: "Select state",
              hidden: contact&.country_code != USA
            ) do |us_state_select|
              us_states.each do |state|
                us_state_select.option(
                  label: state[0],
                  value: state[0],
                  selected: region_of_contact?(state[0])
                )
              end
            end

            state_province_multi.select_list(
              name: :ca_provinces,
              disabled: true,
              autocomplete: "address-level1",
              prompt: "Select province",
              hidden: contact&.country_code != CANADA
            ) do |province_select|
              canada_provinces.each do |province|
                province_select.option(
                  label: province,
                  value: province,
                  selected: region_of_contact?(province)
                )
              end
            end

            state_province_multi.text_field(
              name: :region,
              value: contact&.region,
              disabled: true,
              maxlength: 64,
              autocomplete: "address-level1",
              hidden: contact&.country_code == USA || contact&.country_code == CANADA
            )
          end

          country_region_group.text_field(
            name: :postal_code,
            label: GitHub::HTMLSafeString.make("Postal/Zip code <span class='text-normal'>(9-digit zip code for US)</span>"),
            required: postal_code_required?,
            maxlength: 32,
            disabled: disable_form_inputs,
            autocomplete: "postal-code",
            caption: "Required for certain countries",
            **attributes_for(:postal_code)
          )
        end

        if show_vat_code_for_user?
          name_address_form.fields_for(vat_fields_for, nested: false) do |builder|
            Billing::Settings::VatCodeForm.new(
              builder,
              disabled: disable_form_inputs?,
              form_attributes: attributes_for(:vat_code),
              value: contact&.vat_code
            )
          end
        end

        if show_billing_email_input?
          name_address_form.fields_for(target_type, target, nested: false) do |builder|
            Billing::Settings::BillingEmailForm.new(
              builder,
              target: target,
              test_selector: "billing-email",
              **email_component_args
            )
          end
        end

        if add_page_flow_input?
          name_address_form.hidden(
            name: :form_loaded_from,
            id: "form-loaded-from",
            value: payment_flow_loaded_from,
            scope_name_to_model: false
          )
        end

        name_address_form.hidden(
          name: :target,
          value: target_type,
          scope_name_to_model: false
        )
        name_address_form.hidden(
          name: target_id_name,
          value: target.display_login,
          scope_name_to_model: false
        )
        name_address_form.hidden(
          name: :contact_type,
          value: contact&.address_type,
          scope_name_to_model: false
        )

        if include_buttons?
          if return_to.present?
            name_address_form.hidden(
              name: :return_to,
              id: "return_to",
              value: return_to,
              scope_name_to_model: false,
              scope_id_to_model: false
            )
          end

          name_address_form.group(layout: :horizontal) do |button_group|
            button_group.submit(
              name: :submit,
              label: "Save billing information",
              scheme: :primary,
              style: "flex: 1; max-width: 50%",
              disabled: disable_form_inputs?,
              test_selector: "submit-personal-profile-button"
            )
            button_group.button(
              name: :reset,
              type: :reset,
              value: "Cancel",
              label: "Cancel",
              hidden: !cancellable,
              style: "flex: 1; max-width: 50%",
              class: "js-cancel-submit-personal-profile-btn js-cancel-billing-info",
              test_selector: "cancel-submit-personal-profile-button",
              data: { action: "click:billing-checkout#cancelEditBillingInformation" }
            )
          end

          if target.organization?
            name_address_form.hidden(
              name: :billing_info_submit_btn,
              scope_name_to_model: false,
              value: "Save and continue",
              test_selector: "submit-button"
            )
          end
        end

        if org_record_is_individual_owned?
          name_address_form.hidden(
            name: :org_record_is_individual_owned,
            id: "org-record-is-individual-owned",
            value: "Yes",
            scope_name_to_model: false,
            scope_id_to_model: false
          )
        end
      end

      attr_reader :payment_flow_loaded_from, :disable_form_inputs,
        :contact, :return_to, :target, :form_id, :actor, :show_org_fields, :invoice_download_available,
        :show_vat_code_for_user, :email_component_args, :include_buttons, :cancellable

      alias disable_form_inputs? disable_form_inputs
      alias include_buttons? include_buttons

      def initialize(
        contact:,
        target:,
        payment_flow_loaded_from: "NEW_FLOW",
        disable_form_inputs: false,
        return_to: nil,
        email_component_args: {},
        actor: nil,
        show_org_fields: false,
        include_buttons: false,
        cancellable: false
      )
        @contact = contact
        @target = target
        @payment_flow_loaded_from = payment_flow_loaded_from
        @disable_form_inputs = disable_form_inputs
        @return_to = return_to
        @email_component_args = email_component_args
        @actor = actor # an actor present means the record is owned by the actor (user) who isn't the target
        @show_org_fields = show_org_fields
        @include_buttons = include_buttons
        @cancellable = cancellable
      end

      def add_page_flow_input?
        !payment_flow_loaded_from.blank?
      end

      def attributes_for(field_name)
        update_result.primer_form_attributes_for(field_name)
      end

      def update_result
        @update_result ||= target.contact_information_stash(contact&.address_type || "billing")
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

      def country_of_contact?(country_code)
        contact&.country_code == country_code || update_result.field_value("country_code") == country_code
      end

      def region_of_contact?(state)
        contact&.region == state || update_result.field_value("region") == state
      end

      def show_business_fields?
        target.business?
      end

      def show_org_fields?
        (target.organization? && target.org_is_on_business_tos?) || show_org_fields
      end

      def show_user_fields?
        !show_org_fields? && !target.business?
      end

      def show_vat_code_for_user?
        show_user_fields?
      end

      def show_billing_email_input?
        return false if org_record_is_individual_owned?

        target.organization? || target.business?
      end

      def show_middle_name?
        return false unless contact&.respond_to?(:middle_name)
        contact.middle_name.present?
      end

      memoize def org_record_is_individual_owned?
        # This is true when the billing record is scoped to the user actor instead of the target org
        target.org_is_on_standard_tos? && actor.present? && actor.user?
      end

      def billing_info_form_submit_method
        (target.organization? || target.business?) ? :put : :post
      end

      def target_type
        return :organization if target.organization?

        target.event_prefix
      end

      def target_id_name
        if target.user?
          :user_id
        elsif target.organization?
          :organization_id
        elsif target.business?
          :slug
        end
      end

      def vat_fields_for
        # return nil as we want vat_code to be a root param `params[:vat_code]`
        return nil if target.feature_enabled?(:read_billing_information_from_contacts)
        :account_screening_profile
      end

      memoize def vat_code_required?
        target.vat_code_required_geo?
      end

      memoize def postal_code_required?
        target.postal_code_required_geo?
      end
    end
  end
end
