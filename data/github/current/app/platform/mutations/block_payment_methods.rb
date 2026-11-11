# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class BlockPaymentMethods < Platform::Mutations::Base
      docs_category :billing

      description "Block payment methods by card fingerprints"

      visibility :internal
      minimum_accepted_scopes ["site_admin"]
      extras [:execution_errors]

      read_arguments_from_replicas!

      argument :card_fingerprints, [String], "The card fingerprints to block", required: true
      argument :consequence, Enums::BlockedPaymentMethodConsequence, "The consequence to apply to accounts that add one of the blocked payment methods", required: false, default_value: "suspended"
      argument :apply_to_current_users, Boolean, "Whether to apply the consequence to accounts currently using the payment methods", required: false, default_value: true

      field :results, [Objects::BlockPaymentMethodResult], "The per-fingerprint results of the block operation", null: true

      def resolve(**inputs)
        unless self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have permission to block payment methods"
        end

        card_fingerprints = T.must(inputs[:card_fingerprints])
        consequence = BlacklistedPaymentMethod::Consequence.deserialize(T.must(inputs[:consequence])) # rubocop:disable Naming/InclusiveLanguage
        apply_to_current_users = inputs[:apply_to_current_users]

        results = card_fingerprints.map do |card_fingerprint|
          begin
            Billing::Stafftools::BlockPaymentMethod.new(card_fingerprint:, consequence:, apply_to_current_users:, actor: context[:viewer]).call
            { card_fingerprint:, blocked: true, error: nil }
          rescue ActiveRecord::RecordNotFound
            { card_fingerprint:, blocked: false, error: "Payment method could not be found with card fingerprint: #{card_fingerprint}" }
          end
        end

        { results: results }
      end
    end
  end
end
