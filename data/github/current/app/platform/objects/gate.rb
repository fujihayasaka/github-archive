# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Gate < Platform::Objects::Base
      description "An environment gate."
      visibility :internal

      implements_node templates: [[:g, :repository_id, :id]], as: "GA", ready_date: "2022-03-01" do |gate|
        gate.async_environment.then do |environment|
          raise Platform::Errors::NotFound, "Environment not found for the given gate: #{gate.id}" if environment.nil?
          {
            prefix: :g,
            repository_id: environment.repository_id,
            id: gate.id
          }
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, check_run)
        # No special API permissions
        permission.hidden_from_public?(self) # Update this authorization if we ever go public with this object
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, gate)
        # No special API permissions
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      database_id_field

      field :type, Enums::GateType, description: "The type of gate.", null: false

      field :timeout, Integer, description: "The timeout in minutes for this gate.", null: false
    end
  end
end
