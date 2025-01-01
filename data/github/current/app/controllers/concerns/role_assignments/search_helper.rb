# typed: strict
# frozen_string_literal: true

module RoleAssignments
  module SearchHelper
    extend ActiveSupport::Concern
    extend T::Helpers

    class SelectedTab < T::Enum
      enums do
        Team = new("team")
        User = new("user")
      end
    end

    requires_ancestor { ApplicationController }

    abstract!

    sig { abstract.returns(ActionController::Parameters) }
    def params; end

    private

    FILTER_FIELDS = %i[is].freeze

    sig { returns([SelectedTab, T.nilable(String)]) }
    def parse_search_query
      input_query = params[:query].to_s
      return [SelectedTab::User, nil] if input_query.blank?

      parsed_query_params = Search::ParsedQuery.parse(input_query, terms: FILTER_FIELDS)

      query_hash = {}
      parsed_query_params.each do |key, value|
        if value.nil? # the key is just a string (e.g. "foo") - this is the search query
          query_hash[:query] = key
          next
        end
        query_hash[key] = value
      end

      selected_tab = if query_hash[:is] == SelectedTab::Team.serialize
        SelectedTab::Team
      else
        SelectedTab::User
      end

      [selected_tab, query_hash[:query]]
    end
  end
end
