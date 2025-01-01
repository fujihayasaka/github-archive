# typed: true
# frozen_string_literal: true

module Platform::Objects::Query::CodeSearch
  extend ActiveSupport::Concern
  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames

  included do
    T.bind(self, T.class_of(Platform::Objects::Query))
    field :code_search,
      Connections::CodeSearch,
      mobile_only: true,
      null: false,
      connection: false,
      description: "Searches for query terms inside of a file and file names." do
      has_connection_arguments
      argument :query, String, "One or more search keywords and qualifiers. Qualifiers allow you to limit your search to specific areas of GitHub.", required: true
    end

    def code_search(**arguments)
      T.bind(self, T.any(Platform::Objects::Query, Platform::ConnectionWrappers::CodeSearchQuery))
      ConnectionWrappers::CodeSearchQuery.new(
        nil,
        first: arguments[:first],
        last: arguments[:last],
        after: arguments[:after],
        before: arguments[:before],
        arguments: arguments,
        context:
      )
    end
  end
end
