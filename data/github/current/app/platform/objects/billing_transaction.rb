# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class BillingTransaction < Platform::Objects::Base
      model_name "Billing::BillingTransaction"
      description "An account's billing transaction, representing something they paid for."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        return false unless permission.viewer
        object.async_live_user.then do
          account = object.user

          if account.id == permission.viewer.id
            true
          elsif account.organization? && account.billing_manager?(permission.viewer)
            true
          else
            permission.viewer.owned_organizations.include? account
          end
        end
      end

      visibility :internal
      minimum_accepted_scopes ["user"]

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      global_id_field :id, description: "The Node ID of the BillingTransaction object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      field :amount_in_cents, Integer, "The cost in cents of this transaction.", null: false
      field :created_at, Scalars::DateTime, "The datetime this transaction was created.", null: false
      field :paypal_email, String, "The paypal e-mail associated with the transaction.", null: true
      field :bank_identification_number, Integer, "The bank identification number tied to the transaction.", null: true
      field :last_four, String, "Last four of the card tied to the transaction.", null: true
      field :transaction_id, String, "ID tied to the payment transaction.", null: true
      field :is_paypal, Boolean, "Is the transaction tied to a paypal account?", method: :paypal?, null: false
      field :status, String, "The status of this transaction.", null: true, method: :last_status
      field :is_voided, Boolean, "Has the transaction been voided?", method: :voided?, null: false
      field :is_refunded, Boolean, visibility: :internal, description: "Has the transaction been refunded?", null: false

      def is_refunded
        @object.async_refund.then do
          @object.was_refunded?
        end
      end

      field :refund_amount_in_cents, Integer, visibility: :internal, description: "The amount of cents refunded if the transaction was refunded", null: false

      def refund_amount_in_cents
        @object.async_refund.then do |refund|
          if refund.present?
            -(refund.amount_in_cents)
          else
            0
          end
        end
      end

      field :is_charged_back, Boolean, "Has the transaction been charged back?", method: :charged_back?, null: false
      field :is_success, Boolean, "Was the transaction successful?", method: :success?, null: false
      field :card_type, String, "The type of card used", null: true

      field :account, Platform::Unions::Account, visibility: :internal, method: :async_live_user, description: "The account associated with this subscription item", null: true
    end
  end
end
