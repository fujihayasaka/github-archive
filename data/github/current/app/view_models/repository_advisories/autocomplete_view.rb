# typed: true
# frozen_string_literal: true

module RepositoryAdvisories
  class AutocompleteView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :query, :current_repository, :organization

    delegate :user_query?, :email_query?, to: :autocomplete_query

    def suggestions?
      suggestions.any?
    end

    def personal?
      !organization
    end

    def suggestions
      @suggestions ||= autocomplete_query.suggestions.select do |suggestion|
        # The autocomplete query may return users or teams that don't have
        # access to this repository. Let's make sure they do before we return
        # them.
        current_repository.readable_by?(suggestion)
      end
    end

    private

    def autocomplete_query
      @autocomplete_query ||= AutocompleteQuery.new(
        current_user,
        query,
        organization: organization,
        include_teams: true,
      )
    end
  end
end
