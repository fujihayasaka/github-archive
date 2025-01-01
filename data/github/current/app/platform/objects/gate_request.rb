# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class GateRequest < Platform::Objects::Base
      description "A gate request."
      visibility :internal

      implements_node templates: [[:gr, :repository_id, :id]], as: "GR", ready_date: "2022-03-01" do |gr|
        gr.async_check_run.then do |check_run|
          check_run.async_repository.then do |repository|
            {
              prefix: :gr,
              repository_id: repository.id,
              id: gr.id
            }
          end
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
      def self.async_viewer_can_see?(permission, object)
        object.async_check_run.then do |check_run|
          permission.typed_can_see?("CheckRun", check_run)
        end
      end

      scopeless_tokens_as_minimum

      database_id_field

      field :state, Enums::GateRequestState, description: "The state of the gate", null: false

      field :token, String, description: "The token for Actions Service", null: false
    end
  end
end
