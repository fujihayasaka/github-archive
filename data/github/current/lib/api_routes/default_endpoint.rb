# typed: true
# frozen_string_literal: true

module ApiRoutes
  class DefaultEndpoint
    include Comparable

    attr_reader :verb, :service_mapping

    def initialize(verb, pattern, params, service_mapping: nil)
      @verb = verb
      @pattern = pattern
      @params = params.dup
      @service_mapping = service_mapping
    end

    def to_s
      "#{verb} #{route}"
    end

    def route
      @route ||= routify(pattern, params)
    end

    def <=>(other)
      to_s <=> other.to_s
    end

    private

    attr_reader :pattern, :params

    def routify(pattern, params)
      # When introspecting Sinatra routes, the route pattern is provided as a regex.
      # This turns the string-representation of the regex into a more human-readable
      # route in the format: GET /a/b/:c/d
      pattern.to_s
      .sub("(?-mix:^\\", "")
      .sub("(?-mix:\\A", "")
      .sub("(?-mix:", "")
      .sub("\\z)", "")
      .sub("$)", "")
      .gsub("(?:\\-|%2[Dd])", "-")
      .gsub("\\/", "/")
      .gsub("([^\/?#]+)") { ":#{params.shift}" } # insert params into route
    end
  end
end
