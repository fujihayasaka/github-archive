# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class ContributionCollector < Platform::Loader
      def self.load(
        contribution_classes: nil,
        organization_id:,
        time_range:,
        user:,
        viewer:,
        excluded_organization_ids: [],
        lightweight: false
      )
        # Compacting here will remove keys with nil values
        # This allows us to use fall back to the default values
        # within the Contribution::Collector constructor
        normalized_args = {
          contribution_classes: contribution_classes,
          organization_id: organization_id,
          time_range: time_range,
          user: user,
          viewer: viewer,
          excluded_organization_ids: excluded_organization_ids,
          lightweight: lightweight,
        }.compact

        self.for.load(normalized_args)
      end

      def fetch(all_the_args)
        # Use the calendar time range as the default, so the Activity Overview
        # uses the same Collector, and therefore the same time range
        now = Time.zone.now
        past_year = Contribution::Calendar.time_range_ending_on(now)

        all_the_args.each_with_object({}) do |args, collectors|
          collectors[args] = Contribution::Collector.new(
            **args.reverse_merge(time_range: past_year),
          )
        end
      end
    end
  end
end
