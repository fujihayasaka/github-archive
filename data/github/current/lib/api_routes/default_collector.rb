# typed: true
# frozen_string_literal: true
module ApiRoutes
  module DefaultCollector
    def self.endpoints_in(namespace)
      endpoints = []

      namespace.routes.each_pair do |verb, routes|
        # These correlate to GET requests
        next if verb == "HEAD"

        routes.each do |pattern, params, _, _|
          method_name = "#{verb.to_s.upcase} #{pattern}"
          service_mapping = namespace.service_mapping(method_name)
          endpoints << DefaultEndpoint.new(verb, pattern, params, service_mapping: service_mapping)
        end
      end
      endpoints
    end
  end
end
