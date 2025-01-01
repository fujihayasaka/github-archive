# typed: true
# frozen_string_literal: true

module Platform
  module PersistedQueryTracer
    attr_reader :stats

    def execute_query(query:)
      @stats = {}
      super
    end

    def set_stats(elapsed_time, type_name, field_path)
      @stats[type_name] ||= { count: 0, time: 0, paths: {} }
      @stats[type_name][:count] += 1
      @stats[type_name][:time] += elapsed_time
      @stats[type_name][:paths][field_path] ||= 0
      @stats[type_name][:paths][field_path] += 1
    end

    def create_path_string(current_path)
      return "" if current_path.nil? || current_path.empty?
      current_path_without_numbers = current_path.select { |item| item.is_a?(String) }
      current_path_without_numbers.join(" > ")
    end

    def authorized(query:, type:, object:)
      start_time = GitHub::Dogstats.monotonic_time
      res = super
      set_stats(
        GitHub::Dogstats.monotonic_time - start_time,
        object.class,
        create_path_string(query.context.namespace(:interpreter)[:current_path])
      )
      res
    end

    def authorized_lazy(query:, type:, object:)
      start_time = GitHub::Dogstats.monotonic_time
      res = super
      set_stats(
        GitHub::Dogstats.monotonic_time - start_time,
        object.class,
        create_path_string(query.context.namespace(:interpreter)[:current_path])
      )
      res
    end
  end
end
