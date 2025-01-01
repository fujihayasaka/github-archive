# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    class BusinessUseBillingInformationForShippingForm < ApplicationForm

      form do |use_billing_information_for_shipping|
        T.bind(self, BusinessUseBillingInformationForShippingForm)

        use_billing_information_for_shipping.check_box(
          name: :same_as_billing,
          label: "Shipping information is the same as billing information",
          mb: 3,
          data: {
            target: "business-shipping-information.sameAsBillingCheckbox",
            action: "change:business-shipping-information#handleShippingInformationForm"
          }
        )

        use_billing_information_for_shipping.group(layout: :horizontal) do |button_group|
          button_group.submit(
            name: :submit,
            label: "Save",
            scheme: :primary,
            data: { target: "business-shipping-information.sameAsBillingSubmitButton" },
            hidden: true
          )

          if business.shipping_contact.persisted?
            button_group.button(
              name: :cancel,
              type: :button,
              label: "Cancel",
              data: {
                target: "business-shipping-information.sameAsBillingCancelButton",
                action: "click:business-shipping-information#cancelShippingInformationEdit"
              },
              hidden: true
            )
          end
        end
      end

      sig { returns(Business) }
      attr_reader :business

      sig { params(business: Business).void }
      def initialize(business:)
        @business  = business
      end
    end
  end
end
