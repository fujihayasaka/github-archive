# typed: true
# frozen_string_literal: true

module Platform
  class RouteToQueryMapper
    class JsonBackend
      def fetch(route)
        route_query_map.fetch(route) { yield }
      end

      def fetch_variables(query_id)
        if (record = relay_manifest.dig(:queries, query_id))
          record[:params]
        else
          yield
        end
      end

      def read_json_file(path)
        if path.exist?
          JSON.parse(path.read)
        else
          {}
        end
      end

      # A hash keyed by routes identifiers and valued with graphql query ids.
      def route_query_map
        relay_manifest[:routes]
      end

      def get_matching_url_pattern(route)
        literal_match = route_query_map.fetch(route, nil)
        if !literal_match.nil?
          return {
            url: route,
            named_captures: {}
          }
        end

        urls = route_query_map.keys
        urls.each do |url|
          regex_string = "^#{url.gsub(/:([A-Za-z0-9_.-]+)/) do
            name = $1
            pattern = name == 'number' ? '\d+' : '[A-Za-z0-9_.%-]+'
            "(?<#{name}>#{pattern})"
          end}\/?(?:\\?.*)?$"

          regex = Regexp.new(regex_string)
          match = regex.match(route)
          if match
            return {
              url: url,
              named_captures: match.named_captures
            }
          end
        end
        nil
      end

      private

      def relay_manifest
        GitHubUI::Manifest.new.relay_manifest
      end
    end
  end
end
