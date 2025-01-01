# typed: true
# frozen_string_literal: true

module Businesses
  class ExternalGroupsView < Businesses::QueryView
    # query filters defined for QueryView
    attr_reader :business, :sync_status

    def initialize(**args)
      super(args)
      @business = args[:business]
    end

    def filter_map
      BusinessesHelper::EXTERNAL_GROUPS_QUERY_FILTERS
    end
  end
end
