# typed: true
# frozen_string_literal: true

module Api
  class RouteActor
    include GitHub::FlipperActor
    include GitHub::VexiActor

    attr_reader :flipper_id

    # ID should match the format of the route name used in env["github.api.route"], but
    # spaces are not allowed in Flipper IDs, and colons are special, so we replace them
    # with underscores e.g. "GET_/repositories/_repository_id/check-runs"
    def self.find_by_id(id) # rubocop:disable GitHub/FindByDef
      new(id)
    end

    # Initialize with route pattern from the env
    # e.g. "GET /repositories/:repository_id/check-runs"
    # if no route is found, return a new RouteActor with nil id ("RouteActor:")
    def self.from_env(env)
      route_pattern = env["github.api.route"]
      if route_pattern.nil?
        GitHub.logger.warn("No route_pattern found for RouteActor")
        return new(nil)
      end
      new(route_pattern)
    end

    # Initialize with a route ID
    # e.g. "GET /repositories/:repository_id/check-runs"
    def initialize(id)
      # Replace non-alphanumeric, non-/, non-_, non-., non-- characters with underscore
      # Colons are allowed, but have special meaning.
      sanitized_id = "#{self.class.name}:#{id.to_s.gsub(/[^a-zA-Z0-9\/._-]/, '_')}"

      @flipper_id = sanitized_id
      @vexi_id = sanitized_id
    end

    def ==(other)
      self.class == other.class && vexi_id == other.vexi_id
    end
    alias_method :eql?, :==

    def to_s
      @vexi_id
    end

    def vexi_id
      @vexi_id
    end
  end
end
