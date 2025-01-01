# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class BlockPaymentMethodAndSuspendUsersByCardFingerprint < Platform::Mutations::Base
      extend T::Sig

      description "Block payment method and suspend users by card fingerprint"

      visibility :internal
      minimum_accepted_scopes ["site_admin"]
      extras [:execution_errors]

      argument :card_fingerprint, String, "The card fingerprint we want to block and suspend associated users for", required: true

      field :success, Boolean, "Did the block and suspension get applied successfully?", null: true

      def resolve(**inputs)
        unless self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have permission to block payment method and suspend users by card fingerprint"
        end

        card_fingerprint = T.must(inputs[:card_fingerprint])
        Billing::Stafftools::BlockCardFingerprintAndSuspendUsers.new(card_fingerprint:, actor: context[:viewer]).call

        {
          success: true
        }
      rescue ActiveRecord::RecordNotFound
        raise Platform::Errors::NotFound.new("Payment method could not be found with signature")
      end
    end
  end
end
