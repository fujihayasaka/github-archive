# typed: false
# frozen_string_literal: true

module Platform
  module PersistedQueryTracer
    attr_reader :stats

    def execute_query(query:)
      @stats = Hash.new {}
      super
    end

    def set_stats(elapsed_time, type_name)
      @stats[type_name] ||= { count: 0, time: 0 }
      @stats[type_name][:count] += 1
      @stats[type_name][:time] += elapsed_time
    end

    def authorized(query:, type:, object:)
      start_time = GitHub::Dogstats.monotonic_time
      res = super
      set_stats(
        GitHub::Dogstats.monotonic_time - start_time,
        object.class.to_s
      )
      res
    end

    def authorized_lazy(query:, type:, object:)
      start_time = GitHub::Dogstats.monotonic_time
      res = super
      set_stats(
        GitHub::Dogstats.monotonic_time - start_time,
        object.class.to_s
      )
      res
    end
  end
end
