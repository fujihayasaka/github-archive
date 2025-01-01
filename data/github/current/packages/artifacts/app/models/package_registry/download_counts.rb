# typed: true
# frozen_string_literal: true

module PackageRegistry
  class DownloadCounts
    class Null
      def total
        0
      end

      DAY_COUNTS = [0] * 30
      def day_counts
        DAY_COUNTS
      end

      def today
        0
      end

      def last_week
        0
      end

      def last_30
        0
      end
    end

    NULL = Null.new

    attr_reader :raw

    delegate :day_counts, :total, to: :raw

    def initialize(download_counts_raw)
      @raw = download_counts_raw
    end

    def today
      @today ||= day_counts[0] || 0
    end

    def last_week
      @last_week ||= day_counts[0..6].sum
    end

    def last_30
      @last_30 ||= day_counts[0..29].sum
    end
  end
end
