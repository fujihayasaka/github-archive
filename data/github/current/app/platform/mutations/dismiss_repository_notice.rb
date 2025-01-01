# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DismissRepositoryNotice < Platform::Mutations::Base
      description "Dismisses a notice for a user, scoped to a repository."

      minimum_accepted_scopes ["user"]

      visibility :internal

      argument :notice, String, "The type of notice to dismiss.", required: true
      argument :repository_id, ID, "The type of notice to dismiss.", required: true, loads: Objects::Repository, as: :repository

      def resolve(**inputs)
        context[:viewer].dismiss_repository_notice(inputs[:notice], repository_id: inputs[:repository].id)
      end
    end
  end
end
