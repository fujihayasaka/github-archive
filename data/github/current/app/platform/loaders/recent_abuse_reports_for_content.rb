# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class RecentAbuseReportsForContent < Platform::Loader
      def self.load(object)
        self.for(object.class).load(object.id)
      end

      def initialize(klass)
        @klass = klass
      end

      def fetch(object_ids)
        results = AbuseReport.where(
          reported_content_type: @klass,
          reported_content_id: object_ids,
        ).order(created_at: :desc).group_by(&:reported_content_id)

        object_ids.each_with_object(results) do |object_id, result|
          result[object_id] ||= ::AbuseReport.none
        end
      end
    end
  end
end
