# typed: true
# frozen_string_literal: true

module OrgRoles
  module Assignment
    class AssigneeAutocompleteComponent < ApplicationComponent
      include AvatarHelper

      sig { params(suggestions: T::Array[T.any(User, Team)]).void }
      def initialize(suggestions:)
        @suggestions = suggestions
      end

      private

      sig { returns(T::Array[T.any(User, Team)]) }
      attr_reader :suggestions

      def suggestion_type(suggestion)
        case suggestion
        when User
          "user"
        when BusinessTeam
          "enterprise team"
        else
          "team"
        end
      end

      def suggestion_value(suggestion)
        "#{suggestion_type(suggestion)}/#{suggestion.id}"
      end

      def suggestion_label(suggestion)
        if suggestion.is_a?(User)
          suggestion.display_login
        else
          suggestion.slug
        end
      end
    end
  end
end
