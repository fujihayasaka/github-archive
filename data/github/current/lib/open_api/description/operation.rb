# typed: true
# frozen_string_literal: true

module OpenApi
  module Description
    class Operation
      DOC_PROPERTY_PATH = %w[externalDocs url].freeze
      OWNER_PROPERTY_PATH = %w[x-github-internal owner].freeze
      HTTP_METHOD_PROPERTY_PATH = %w[x-github-internal http-method].freeze
      ALT_HTTP_METHODS_PROPERTY_PATH = %w[x-github-internal alternative-http-methods].freeze
      ALT_PATHS = %w[x-github-internal alternative-paths].freeze
      PATH_PROPERTY_PATH = %w[x-github-internal path].freeze

      class NotFound < StandardError; end
      class ParseError < StandardError; end

      attr_reader :raw, :path_parameters, :query_parameters, :request_body

      def self.load(operation_id, webhook: false)
        operation_path = find_path(operation_id, webhook: webhook)
        from_path(operation_path, webhook: webhook)
      end

      def self.from_path(path, webhook: false)
        raw_operation = begin
          YAML.load_file(path)
        rescue Errno::ENOENT
          raise NotFound, "No operation description at #{path}"
        rescue Psych::SyntaxError => e
          raise ParseError,  "Error parsing #{path}: #{e.message}"
        end

        new(raw_operation, webhook: webhook).tap do |operation|
          operation.expand!
        end
      end

      def self.find_path(operation_id, webhook:)
        source_dir = webhook ? "webhooks" : "operations"
        if GitHub.openapi_include_test_fixtures?
          fixture_file = Rails.root.join("test", "fixtures", "open_api", source_dir, "#{operation_id}.yaml")
          return Rails.root.join(fixture_file) if File.exist?(fixture_file)
        end

        OpenApi.root.join(source_dir, "#{operation_id}.yaml")
      end

      def source_path
        if @raw.key?("$ref") && @raw["$ref"].start_with?(source_dir)
          OpenApi.root.join(OpenApi.release.filename).to_s
        else
          if GitHub.openapi_include_test_fixtures? && File.exist?(Rails.root.join("test", "fixtures", "open_api", source_dir, "#{id}.yaml"))
            Rails.root.join("test", "fixtures", "open_api", source_dir, "#{id}.yaml")
          else
            OpenApi.root.join(source_dir, "#{id}.yaml")
          end
        end
      end

      def source_dir
        webhook? ? "webhooks" : "operations"
      end

      def expand!(parent: nil, parent_key: nil)
        return if expanded?

        @raw = OpenApi::Description::Expander.expand(
          @raw,
          source_path,
          parent: parent,
          parent_key: parent_key,
        )

        unless OpenApi.performing_transform?
          @raw = OpenApi::Description::Expander.deep_freeze(@raw)
        end

        build_parameters
        build_request_body
        @expanded = true

        @raw
      end

      def webhook?
        @webhook
      end

      def expanded?
        @expanded
      end

      def initialize(operation, webhook: false, ignored: false)
        @webhook          = webhook
        @ignored          = ignored
        @raw              = ignored? ? {} : operation
        @expanded         = check_for_refs(@raw)
        @path_parameters  = {}
        @query_parameters = {}
        build_parameters
        build_request_body
      end

      def build_parameters
        (@raw["parameters"] || []).each_with_index do |param, index|
          if param["in"] == "path"
            @path_parameters[param["name"]] = Parameter.new(param, index)
          elsif param["in"] == "query"
            @query_parameters[param["name"]] = Parameter.new(param, index)
          end
        end
      end

      def build_request_body
        @request_body = RequestBody.new(@raw["requestBody"]) if @raw["requestBody"]
      end

      def version_applied?
        false
      end

      def id
        @raw["operationId"]
      end

      def responses
        Responses.new(@raw["responses"]) if @raw["responses"]
      end

      def path
        @raw.dig(*PATH_PROPERTY_PATH)
      end

      def route_owner
        @raw.dig(*OWNER_PROPERTY_PATH)
      end

      def documentation_url
        @raw.dig(*DOC_PROPERTY_PATH)
      end

      def http_method
        @raw.dig(*HTTP_METHOD_PROPERTY_PATH)
      end

      def alternative_http_methods
        @raw.dig(*ALT_HTTP_METHODS_PROPERTY_PATH) || []
      end

      def alternative_paths
        @raw.dig(*ALT_PATHS) || []
      end

      def ignored?
        !!@ignored
      end

      def deprecated?
        !!@raw["deprecated"]
      end

      def has_enterprise_release?
        releases.any? { |element| element.is_a?(Hash) && element.key?("ghes") }
      end

      def releases
        @raw.dig("x-github-releases") || []
      end

      private

      def check_for_refs(value)
        case value
        when Hash
          return false if value.keys.include?("$ref")
          value.each { |_k, v| return check_for_refs(v) }
        when Array
          value.each { |i| return check_for_refs(i) }
        end
      end
    end
  end
end
