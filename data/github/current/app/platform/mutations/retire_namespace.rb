# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RetireNamespace < Platform::Mutations::Base
      description "Retires a namespace."

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :owner_login, String, "The owning user or organization's login", required: true
      argument :name, String, "The retired repository name", required: true

      field :retired_namespace, Objects::RetiredNamespace, "The retired namespace.", null: true

      def resolve(**inputs)
        unless context[:viewer].site_admin?
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to retire a namespace.")
        end

        result = RetiredNamespace.retire(
          owner: inputs[:owner_login],
          name: inputs[:name],
        )

        if result.success?
          { retired_namespace: result.namespace }
        else
          raise Errors::Unprocessable.new(result.errors.to_sentence)
        end
      end
    end
  end
end
