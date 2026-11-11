# typed: true
# frozen_string_literal: true

module GitHub
  module Reports
    class Cache
      def initialize(name, report)
        @name   = name
        @report = report
      end

      def cache_key
        key = "%s:%s:%s" % ["stafftools-report", "v1", @name]
        Digest::SHA256.hexdigest(key)
      end

      def cached?
        !data.nil?
      end

      def data
        @data ||= GitHub.cache.get(cache_key)
      end

      def update
        StafftoolsReportJob.perform_later(@name, GitHub.cache.skip)
      end

      def clear
        GitHub.cache.delete(cache_key)
      end

      def update!
        @data = nil

        GitHub.cache.set(cache_key, @report.data, 1.hour)
      end
    end
  end
end
