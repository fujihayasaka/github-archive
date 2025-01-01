# typed: true
# frozen_string_literal: true
module Billing
  module Settings
    class NameAddressFormInputsComponent < ApplicationComponent
      WRAPPER_TYPES = [:fields, :form].freeze
      DEFAULT_WRAPPER_TYPE = :fields

      attr_reader :profile, :target, :wrapper_type, :form_id, :actor, :system_arguments, :cancellable

      def initialize(
        profile:,
        target:,
        wrapper_type: DEFAULT_WRAPPER_TYPE,
        form_id: nil,
        actor: nil,
        cancellable: false,
        **system_arguments
      )
        @profile = profile
        @target = target
        @wrapper_type = fetch_or_fallback(WRAPPER_TYPES, wrapper_type, DEFAULT_WRAPPER_TYPE)
        @form_id = form_id || "billing-settings-name-address-form-#{target}"
        @actor = actor # an actor present means the record is owned by the actor (user) who isn't the target
        @system_arguments = system_arguments
        @cancellable = cancellable
      end

      def render?
        return true if actor.blank?
        return true unless target.org_is_on_standard_tos?
        return true unless target.has_linked_trade_screening_record?

        actor.has_trade_screening_record_linked_to_org?(organization: target)
      end

      private

      def use_form_for?
        wrapper_type == :form
      end

      def get_form(&block)
        if use_form_for?
          return primer_form_with(
            model: profile,
            url: billing_info_form_submit_path,
            method: billing_info_form_submit_method,
            html: { id: form_id },
            &block
          )
        end

        primer_fields_for :account_screening_profile, profile, &block
      end

      def billing_info_form_submit_path
        if target.organization?
          org_trade_screening_update_path(target)
        elsif target.business?
          billing_settings_update_payment_information_enterprise_path(slug: target)
        else
          trade_screening_record_update_path
        end
      end

      def billing_info_form_submit_method
        (target.organization? || target.business?) ? :put : :post
      end
    end
  end
end
