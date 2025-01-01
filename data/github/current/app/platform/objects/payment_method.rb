# typed: strict
# frozen_string_literal: true

module Platform
  module Objects
    class PaymentMethod < Platform::Objects::Base
      extend T::Sig

      description "The user's default payment method"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig do
        params(permission: Platform::Authorization::Permission, _object: T.untyped)
          .returns(T.any(T::Boolean, Promise[T::Boolean]))
      end
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig do
        params(
          permission: Platform::Authorization::Permission,
          object: ::PaymentMethod,
        ).returns(T.any(T::Boolean, Promise[T::Boolean]))
      end
      def self.async_viewer_can_see?(permission, object)
        return false unless permission.viewer
        return true if object.user_id == permission.viewer.id

        # actually an Organization, probably
        object.async_user.then do |account|
          next true if account.organization? && account.billing_manager?(permission.viewer)

          # TODO: Move this check into a loader.
          permission.viewer.owned_organizations.include? account
        end
      end

      visibility :internal
      minimum_accepted_scopes ["user"]

      global_id_field :id, description: "The Node ID of the PaymentMethod object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      field :formatted_number, String, description: "The formatted and sanitized credit card number; e.g. ****-0001", null: true

      field :card_last_four_digits, String, method: :last_four, description: "Last four digits of the credit card number", null: true

      field :expiration_date, Scalars::DateTime, "The expiration date of the credit card", null: true

      field :formatted_expiration_date, String, description: "The formatted expiration date of the card.", null: true do
        T.bind(self, Platform::Objects::Base::Field)

        argument :format, String, "The format the expiration date should be returned in. Defaults to: %-m/%Y", required: false, default_value: "%-m/%Y"
      end
      sig { params(format: String).returns(String) }
      def formatted_expiration_date(format:)
        expiration_date = object.expiration_date

        return "" unless expiration_date
        expiration_date.strftime(format)
      end

      field :card_type, String, description: "The type of credit card (Visa/MasterCard/etc)", null: true

      field :is_paypal, Boolean, method: :paypal?, description: "Is this a PayPal payment method?", null: false

      field :paypal_email, String, description: "On PayPal, the account's email address", null: true

      field :is_valid, Boolean, visibility: :internal, method: :valid_payment_token?, description: "Does the payment method have a valid token?.", null: false
    end
  end
end
