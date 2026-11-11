# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class LastAbuseReportedAt < Platform::Loader
      def self.load(object)
        self.for(object.class).load(object.id)
      end

      def initialize(klass)
        @klass = klass
      end

      def fetch(object_ids)
        AbuseReport.where(
          reported_content_type: @klass,
          reported_content_id: object_ids,
        ).group(:reported_content_id).maximum(:created_at)
      end
    end
  end
end
