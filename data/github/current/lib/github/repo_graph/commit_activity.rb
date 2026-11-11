# typed: true
# frozen_string_literal: true

require "date"

module GitHub
  module RepoGraph
    class CommitActivity
      def initialize(repo, cache)
        @repo = repo
        @cache = cache
      end

      attr_reader :cache

      def name
        "commit-activity"
      end

      def cache_key
        "%s:%s:%s:%s:%s" % [
          "v5",
          Date.today.to_s,
          @repo.network_id,
          @repo.default_oid,
          name,
        ]
      end

      def empty?(check = data)
        check.empty?
      end

      def data
        data = []
        weeks.each do |week|
          days = []
          total = 0
          week_data = @cache.data.select { |i| i[1] == week }

          if week_data.empty?
            days = [0] * 7
          else
            0.upto(6) do |nday|
              count = week_data.count do |i|
                Time.at(i[0]).localtime(i[5] || 0).wday == nday
              end

              total += count
              days << count
            end
          end

          data << { "days" => days, "total" => total, "week" => week }
        end
        data
      end

      def weeks
        if @cache.weeks.size >= 52
          @cache.weeks.last(52)
        elsif @cache.weeks.any?
          first_week_with_data = Time.at(@cache.weeks[0])
          weeks_diff = 52 - @cache.weeks.size

          weeks = []
          weeks_diff.times do |i|
            weeks << (first_week_with_data - (weeks_diff - i).weeks).to_i
          end
          weeks.concat(@cache.weeks)
          weeks
        else
          []
        end
      end
    end
  end
end
