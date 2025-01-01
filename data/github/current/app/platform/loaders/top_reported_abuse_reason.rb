# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class TopReportedAbuseReason < Platform::Loader
      def self.load(object)
        self.for(object.class).load(object.id)
      end

      def initialize(klass)
        @klass = klass
      end

      def fetch(object_ids)
        results = AbuseReport.connection.select_rows(Arel.sql(<<-SQL, klass: @klass, object_ids: object_ids))
          SELECT ar.reported_content_id, ar.reason
          FROM abuse_reports ar
          WHERE ar.reported_content_type = :klass
            AND ar.reported_content_id IN (:object_ids)
            AND reason = (
              SELECT ar2.reason FROM abuse_reports ar2
              WHERE ar2.reported_content_type = :klass
                AND ar2.reported_content_id = ar.reported_content_id
              GROUP BY reason
              ORDER BY count(*) DESC
              LIMIT 1
            )
          GROUP BY ar.reported_content_id
        SQL

        hash = {}

        results.each do |object_id, reason_enum|
          hash[object_id] = AbuseReport.reasons.key(reason_enum)
        end

        hash
      end
    end
  end
end
