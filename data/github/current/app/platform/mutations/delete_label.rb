# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteLabel < Platform::Mutations::Base
      description "Deletes a label."

      minimum_accepted_scopes ["public_repo"]

      argument :id, ID, "The Node ID of the label to be deleted.", required: true, loads: Objects::Label, as: :label

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, label:, **inputs)
        repository = label.repository
        permission.typed_can_modify?("DeleteLabelByName", repository: repository)
      end

      def resolve(label:, **inputs)

        repository = label.repository

        context[:permission].authorize_content(:label, :delete, repository: repository)

        label.destroy

        {}
      end
    end
  end
end
