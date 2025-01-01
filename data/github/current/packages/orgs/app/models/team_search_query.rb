# typed: true
# frozen_string_literal: true

class TeamSearchQuery
  VISIBILITY_FILTER = /visibility:(secret|visible)/
  MEMBERS_FILTER    = /members:(empty|me)/
  USERS_FILTER      = /@([\w\-\.]+)/
  USER_FILTER_MAX   = 3

  attr_reader :query

  # Public: Initializes TeamSearchQuery object
  #
  # query        - a string used to extract filters from.
  #                filters can be used to pass to graphql
  def initialize(query)
    @query = query.to_s
  end

  def visibility_filter
    VISIBILITY_FILTER.match(query).try(:[], 1)
  end

  def members_filter
    MEMBERS_FILTER.match(query).try(:[], 1)
  end

  def users_filter
    query.scan(USERS_FILTER)
         .first(USER_FILTER_MAX)
         .map { |name, _| name }
         .uniq
  end

  # Return a String that strips all the filters from the query
  def cleaned_query
    query.gsub(VISIBILITY_FILTER, "").gsub(USERS_FILTER, "").gsub(MEMBERS_FILTER, "")
  end
end
