# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DismissNotice < Platform::Mutations::Base
      description "Dismisses a notice for a user."

      minimum_accepted_scopes ["user"]

      visibility :internal

      argument :notice, String, "The type of notice to dismiss.", required: true

      def resolve(**inputs)
        context[:viewer].dismiss_notice(inputs[:notice])
      end
    end
  end
end
