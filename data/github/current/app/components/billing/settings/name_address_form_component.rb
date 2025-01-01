# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    class NameAddressFormComponent < ApplicationComponent
      def initialize(target:, payment_flow_loaded_from:, disable_form_inputs: false, wrapper_class: "pb-3", return_to: nil, form_id: nil)
        @target = target
        @payment_flow_loaded_from = payment_flow_loaded_from
        @disable_form_inputs = disable_form_inputs
        @wrapper_class = wrapper_class
        @return_to = return_to
        @form_id = form_id
      end

      private

      attr_reader :target, :payment_flow_loaded_from, :disable_form_inputs, :wrapper_class, :return_to, :form_id

      def render?
        GitHub.billing_enabled?
      end

      def contact
        target.billing_contact
      end
    end
  end
end
