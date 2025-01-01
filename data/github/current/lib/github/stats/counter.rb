# typed: false
# frozen_string_literal: true

module GitHub
  module Stats
    # A counter counts things.  Designed to loosely map to ruby-metrics.  Once
    # other stats objects are added, a lot of this logic will probably move to
    # some core stats bucket thing.
    class Counter
      class << self
        attr_writer :agent, :root_key, :count_field
      end

      def self.agent
        @agent ||= superclass.agent
      end

      def self.root_key
        @root_key ||= superclass.root_key
      end

      def self.count_field
        @count_field ||= superclass.count_field
      end

      def self.fields(*names)
        if names.blank?
          @fields ||= superclass.fields
        else
          @fields = names.freeze
        end
      end

      def self.collect(*periods)
        periods.each do |period|
          agent.collect(period, self)
        end
      end

      self.count_field = "count".freeze

      attr_reader :keys

      def initialize(redis, agent = nil)
        @redis = redis
        @agent = agent || self.class.agent
      end

      def each_field(periods, data = {}, &block)
        time   = data.delete(:time) || Time.now
        prefix = base_key(data)
        @keys  = periods.map { |period| prefixed_key(prefix, period, time) }
        @keys.each do |key|
          fields = recordable_fields_for(key, data)
          fields.each do |field|
            block.call(key, field)
          end
        end
      end

      def read(period = :all, data = {}, field = self.class.count_field)
        key = key(data, GitHub::Stats::PERIODS[period])
        @agent.read_field key, field
      end

      def recordable_fields_for(key, data)
        [self.class.count_field]
      end

      def after_record
      end

      def base_key(data)
        self.class.root_key
      end

      def key(data, period)
        time   = data.delete(:time) || Time.now
        prefixed_key base_key(data), period, time
      end

      def prefixed_key(prefix, period, time)
        "#{prefix}#{time_period(period, time)}"
      end

      def time_period(format, time = Time.now)
        return format if format.empty?
        ":#{time.strftime(format)}"
      end
    end
  end
end
