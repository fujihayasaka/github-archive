# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    class NameAddressFormInputsComponent < ApplicationComponent
      WRAPPER_TYPES = [:fields, :form].freeze
      DEFAULT_WRAPPER_TYPE = :fields

      attr_reader :contact, :target, :wrapper_type, :form_id, :actor, :system_arguments, :cancellable, :use_turbo, :vat_code_error

      def initialize(
        contact:,
        target:,
        wrapper_type: DEFAULT_WRAPPER_TYPE,
        form_id: nil,
        actor: nil,
        cancellable: false,
        use_turbo: false,
        vat_code_error: nil,
        **system_arguments
      )
        @contact = prefill_contact(contact, target)
        @target = target
        @wrapper_type = fetch_or_fallback(WRAPPER_TYPES, wrapper_type, DEFAULT_WRAPPER_TYPE)
        @form_id = form_id || "billing-settings-name-address-form-#{target}"
        @actor = actor # an actor present means the record is owned by the actor (user) who isn't the target
        @system_arguments = system_arguments
        @cancellable = cancellable
        @use_turbo = use_turbo
        @vat_code_error = vat_code_error
      end

      # This prefills the Billing Information section in development mode only
      sig { params(contact: T.nilable(T.any(AccountScreeningProfile, Billing::Contact)), target: Billing::Types::Account).returns(T.nilable(T.any(AccountScreeningProfile, Billing::Contact))) }
      def prefill_contact(contact, target)
        return contact unless Rails.env.development?
        return contact if contact&.persisted?
        return contact if target.new_record?
        contact ||= target.billing_contact
        contact.address1 = "88 Colin P Kelly Jr St"
        contact.region = "California"
        contact.city = "San Francisco"
        contact.country_code = "US"
        contact.postal_code = "94107"
        if target.organization?
          contact.entity_name = "Mona Lisa Org"
        else
          contact.first_name = "Mona"
          contact.last_name = "Lisa"
        end
        contact
      end

      def render?
        return true if actor.blank?
        return true unless target.org_is_on_standard_tos?
        return true unless target.has_linked_billing_contact?

        target.has_linked_billing_contact_to_actor?(actor: actor)
      end

      private

      def use_form_for?
        wrapper_type == :form
      end

      def fields_for_key
        return :billing_contact if target.feature_flag_enabled?(:read_billing_information_from_contacts, default: false)
        :account_screening_profile
      end

      def get_form(&block)
        if use_form_for?
          return primer_form_with(
            model: contact,
            url: billing_info_form_submit_path,
            method: billing_info_form_submit_method,
            html: { id: form_id },
            data: { turbo: use_turbo },
            &block
          )
        end

        primer_fields_for fields_for_key, contact, &block
      end

      def billing_info_form_submit_path
        return billing_info_form_contact_path if target.feature_flag_enabled?(:read_billing_information_from_contacts, default: false)
        if target.organization?
          org_trade_screening_update_path(target)
        elsif target.business?
          billing_settings_update_payment_information_enterprise_path(slug: target)
        else
          trade_screening_record_update_path
        end
      end

      def billing_info_form_contact_path
        if target.organization?
          billing_contact_path(target)
        elsif target.business?
          billing_contact_path(slug: target)
        else
          billing_contact_path
        end
      end

      def billing_info_form_submit_method
        return :post if target.feature_flag_enabled?(:read_billing_information_from_contacts, default: false)
        (target.organization? || target.business?) ? :put : :post
      end
    end
  end
end
