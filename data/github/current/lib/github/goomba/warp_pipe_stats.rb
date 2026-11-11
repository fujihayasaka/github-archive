# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Collect stats for various operations done via WarpPipe#async_call!
  class WarpPipeStats < ActiveSupport::CurrentAttributes
    attribute :events, :stats_bar_enabled

    def enable_stats_bar_tracking
      self.events = []
      self.stats_bar_enabled = true
    end

    def add_event(event)
      return unless stats_bar_enabled

      events << event
    end

    def call_stats
      stats = Hash.new { |hash, label| hash[label] = Stats.new(label) }

      events.each do |event|
        if goomba_stats = event[:context].try(:__stats__)
          goomba_stats.each do |name, count, duration|
            stats[name.demodulize].add(duration, count)
          end
        else
          label = "#{event[:prefix]}##{event[:operation]}"
          stats[label].add(event[:elapsed])
        end
      end

      stats.values
    end

    def call_time
      time = 0.0
      warp_pipe_events.each { |event| time += event[:elapsed] }
      time / 1000
    end

    def call_count
      warp_pipe_events.size
    end

    def warp_pipe_events
      events.select { |event| event[:context].is_a?(WarpPipe) }
    end

    class Stats
      attr_reader :time, :label, :count

      def initialize(label)
        @time = 0.0
        @count = 0
        @label = label
      end

      def add(time, count = 1)
        @time += time
        @count += count
      end
    end
  end
end
