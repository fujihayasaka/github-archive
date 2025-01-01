# typed: false
# frozen_string_literal: true
module ApplicationController::PaginationDependency

  # Represents pagination parameters for the GraphQL parser.
  class GraphQLPaginationParams
    def initialize(params:, page_size:)
      @result = { after: nil, first: page_size }
      @valid = true

      if params[:before] && !valid_cursor?(params[:before])
        @valid = false
      elsif params[:before]
        @result = { before: params[:before], last: page_size }
      elsif params[:after] && !valid_cursor?(params[:after])
        @valid = false
      else
        @result = { after: params[:after].presence, first: page_size }
      end
    end

    def valid?
      @valid
    end

    def to_h
      @result
    end

    private def valid_cursor?(cursor)
      return true if cursor.blank?
      Platform::ConnectionWrappers::CursorGenerator.resolve_cursor(cursor)
      true
    rescue Platform::Errors::Cursor
      false
    end
  end

  # Generates parameters to paginate a GraphQL collection using before & after
  #
  # page_size: The page size to use in pagination
  #
  # Returns a hash of parameters for use in execution
  def graphql_pagination_params(page_size:)
    if params[:before]
      { before: params[:before], last: page_size }
    else
      { after: params[:after].presence, first: page_size }
    end
  end

  # Returns parameters (derived from params[:before] and params[:after]) that can be
  # used to paginate a GraphQL collection.
  #
  # page_size: The page size to use in pagination
  #
  # Returns GraphQLPaginationParams, which exposes to `to_h` method for retrieving
  # valid pagination params, and a `valid?` method for determining whether the
  # result of `to_h` has been sanitized to remove invalid values.
  def valid_graphql_pagination_params(page_size:)
    GraphQLPaginationParams.new(params: params.slice(:before, :after), page_size: page_size)
  end
end
