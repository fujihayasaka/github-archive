# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UnretireNamespace < Platform::Mutations::Base
      description "Unretires a namespace making it available to users."

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :owner_login, String, "The owning user or organization's login", required: true
      argument :name, String, "The retired repository name", required: true

      field :success, Boolean, "Indicates if unretiring the namespace succeeded", null: true

      def resolve(**inputs)
        unless context[:viewer].site_admin?
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to unretire a namespace.")
        end

        result = RetiredNamespace.unretire(
          owner: inputs[:owner_login],
          name: inputs[:name],
        )

        if result.success?
          { success: true }
        else
          raise Errors::Unprocessable.new(result.errors.to_sentence)
        end
      end
    end
  end
end
