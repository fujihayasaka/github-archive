# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class AdvisoryCredit < Platform::Objects::Base
      visibility :under_development
      description "An advisory credit"
      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject
      scopeless_tokens_as_minimum

      global_id_field :id, description: "The Node ID of the AdvisoryCredit object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      def self.async_api_can_access?(permission, advisory_credit)
        permission.hidden_from_public?(self) # Update this authorization if we ever go public with this object
      end

      def self.async_viewer_can_see?(permission, advisory_credit)
        advisory_credit.async_readable_by?(permission.viewer)
      end

      field :advisory, Platform::Interfaces::Advisory, "The advisory in which the user is credited", method: :async_repository_advisory, null: false

      field :recipient, Interfaces::Actor, "A user who is given credit for the advisory", method: :async_recipient, null: false

      field :state, Platform::Enums::AdvisoryCreditState, "The current state of the credit's acceptance", null: false, visibility: :internal

      def state
        object.state.to_s
      end

      field :ghsa_id, String, "The GitHub Security Advisory ID", null: false, visibility: :internal
    end
  end
end
