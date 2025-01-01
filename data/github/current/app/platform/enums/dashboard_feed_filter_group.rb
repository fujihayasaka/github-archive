# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class DashboardFeedFilterGroup < Platform::Enums::Base
      graphql_name "DashboardFeedFilterGroup"
      description "Possible filter options for the dashboard feed"
      required_capabilities [:mobile_only_schema_mask]
      def self.from_filter_name(filter_name)
        values[filter_name.upcase]&.value
      end

      def self.define_filter_groups
        filter_groups = ::Conduit::FeedFilter.all_groups.keys
        unused_groups = %w[ExplicitOnly Posts]

        mobile_filter_groups = filter_groups + unused_groups

        mobile_filter_groups.each do |group|
          value group.upcase, "#{group} filter group", value: group
        end
      end

      define_filter_groups
    end
  end
end
