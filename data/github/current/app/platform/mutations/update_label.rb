# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateLabel < Platform::Mutations::Base
      description "Updates an existing label."

      minimum_accepted_scopes ["public_repo"]

      argument :id, ID, "The Node ID of the label to be updated.", required: true, loads: Objects::Label, as: :label
      argument :color, String, "A 6 character hex code, without the leading #, identifying the updated color of the label.", required: false
      argument :description, String, "A brief description of the label, such as its purpose.", required: false
      argument :name, String, "The updated name of the label.", required: false

      field :label, Objects::Label, "The updated label.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, label:, **inputs)
        repository = label.repository
        permission.typed_can_modify?("UpdateLabelByName", repository: repository)
      end

      def resolve(label:, **inputs)

        repository = label.repository

        context[:permission].authorize_content(:label, :update, repository: repository)

        label.color = inputs[:color] if inputs.key?(:color)
        label.name = inputs[:name] if inputs.key?(:name)
        label.description = inputs[:description] if inputs.key?(:description)

        if label.save # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          { label: label }
        else
          raise Errors::Unprocessable.new(label.errors.full_messages.join(", "))
        end
      end
    end
  end
end
