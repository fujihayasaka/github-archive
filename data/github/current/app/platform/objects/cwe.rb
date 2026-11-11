# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CWE < Platform::Objects::Base

      implements_node templates: [[:c, :id]], as: "CWE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |cwe|
        { prefix: :c, id: cwe.id }
      end

      description "A common weakness enumeration"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, calendar_week)
        # Access to this object is managed by its parent SecurityAdvisory.
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # Access to this object is managed by its parent SecurityAdvisory.
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :cwe_id, String, "The id of the CWE", null: false
      field :name, String, "The name of this CWE", null: false
      field :description, String, "A detailed description of this CWE", null: false
    end
  end
end
