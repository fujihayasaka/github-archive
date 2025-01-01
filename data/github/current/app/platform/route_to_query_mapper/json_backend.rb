# typed: true
# frozen_string_literal: true
module Platform
  class RouteToQueryMapper
    class JsonBackend
      QUERY_MAP_PATH = Rails.root.join("config/route_to_queries_map.json")
      QUERY_PARAM_TO_TYPE_PATH  = Rails.root.join("config/query_param_types.json")
      private_constant :QUERY_MAP_PATH


      def fetch(route)
        route_query_map.fetch(route) { yield }
      end

      def fetch_variables(query_id)
        query_to_param_type_map.fetch(query_id) { yield }
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
        @route_query_map ||= read_json_file(QUERY_MAP_PATH).freeze
      end

      def query_to_param_type_map
        @query_to_param_type_map ||= read_json_file(QUERY_PARAM_TO_TYPE_PATH).freeze
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
          regex_string = "^#{url.gsub(/:([A-Za-z0-9_.-]+)/, '(?<\1>[A-Za-z0-9_.-]+)')}\/?(?:\\?.*)?$"
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
    end
  end
end
