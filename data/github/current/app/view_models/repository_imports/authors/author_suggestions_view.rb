# typed: true
# frozen_string_literal: true

module RepositoryImports
  module Authors
    class AuthorSuggestionsView < ::AutocompleteView
      # Public: Is the author query a valid email?
      #
      # Returns true or false.
      def map_by_email?
        !!(User::EMAIL_REGEX =~ query)
      end
    end
  end
end
