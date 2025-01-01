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

    FILTER_FIELDS = %i[is role].freeze

    sig { params(roles: T::Array[Role]).returns([SelectedTab, T.nilable(String), T.nilable(Role)]) }
    def parse_search_query(roles: [])
      input_query = params[:query].to_s
      return [SelectedTab::User, nil, nil] if input_query.blank?

      parsed_query_params = Search::ParsedQuery.parse(input_query, terms: FILTER_FIELDS)

      query_hash = {}
      parsed_query_params.each do |key, value|
        if value.nil? # the key is just a string (e.g. "foo") - this is the search query
          query_hash[:query] = key
          next
        end
        query_hash[key] = value
      end

      selected_tab = parse_selected_tab(query_hash)
      selected_role = parse_selected_role(query_hash, roles)

      [selected_tab, query_hash[:query], selected_role]
    end

    sig { params(query_hash: T::Hash[Symbol, String]).returns(T.any(RoleAssignments::SearchHelper::SelectedTab::Team, RoleAssignments::SearchHelper::SelectedTab::User)) }
    def parse_selected_tab(query_hash)
      if query_hash[:is]&.downcase == SelectedTab::Team.serialize
        SelectedTab::Team
      else
        SelectedTab::User
      end
    end

    sig { params(query_hash: T::Hash[Symbol, String], roles: T::Array[Role]).returns(T.nilable(Role)) }
    def parse_selected_role(query_hash, roles = [])
      query_role = query_hash[:role]
      return nil unless query_role.present? && roles.any?

      roles.find { |role| role.name == query_role || role.display_name.downcase == query_role.downcase }
    end
  end
end
