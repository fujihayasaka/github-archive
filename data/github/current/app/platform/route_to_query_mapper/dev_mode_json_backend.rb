# typed: true
# frozen_string_literal: true

module Platform
  class RouteToQueryMapper
    # In dev we need to re-read the file every time since it can change
    # throughout the life of the server process.
    class DevModeJsonBackend < JsonBackend
      def route_query_map
        @route_query_map = read_json_file(QUERY_MAP_PATH)
      end

      def query_to_param_type_map
        @query_to_param_type_map = read_json_file(QUERY_PARAM_TO_TYPE_PATH)
      end
    end
  end
end
