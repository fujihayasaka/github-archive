# typed: true
# frozen_string_literal: true

require "hana"
require "yaml"

module OpenApi
  module Description
    class Release
      class Error < ::RuntimeError; end
      class ReleaseNotFoundError < ArgumentError; end

      METHOD_ORDER = %w[get head post put patch delete options trace].freeze

      class OperationRef

        attr_reader :http_path, :http_method, :ref

        def initialize(http_path, http_method, ref)
          @http_path = http_path
          @http_method = http_method
          @ref = ref
        end
      end

      class WebhookRef

        attr_reader :filepath, :name

        def initialize(filepath, name)
          @filepath = filepath
          @name = name
        end
      end

      # Public: Retrieve all defined releases.
      #
      # Returns an Array of Release instances.
      def self.all(include_unpublished:)
        @all ||= OpenApi.root.glob("config/releases/*.yaml").map do |release_patch_file|
          release_identifier = release_patch_file.basename(".yaml").to_s
          parse(release_identifier, include_unpublished: include_unpublished)
        end.compact
      end

      # Public: Retrieve specified releases (or all, if none given).
      #
      # release_identifiers - an Array of String release identifiers (e.g., 'ghes-2.21')
      #
      # Returns an Array of Release instances.
      def self.find_all(release_identifiers = [], include_unpublished: false)
        if release_identifiers.empty?
          all(include_unpublished: include_unpublished)
        else
          release_identifiers.map do |release_identifier|
            release = parse(release_identifier, include_unpublished: include_unpublished)
            if release.exist?
              release
            else
              raise ArgumentError, "No API release defined: #{release_identifier}"
            end
          end
        end
      end

      def self.writers
        @writers ||= {
          unbundled: OpenApi::Description::UnbundledReleaseWriter,
          bundled: OpenApi::Description::BundledReleaseWriter,
          dereferenced: OpenApi::Description::DereferencedReleaseWriter
        }
      end

      def self.parse(identifier, include_unpublished:, include_test_fixtures: false, merge_ghec_operations: false)
        name, version = identifier.split("-", 2)
        new(name, version: version, include_unpublished: include_unpublished, include_test_fixtures: include_test_fixtures, merge_ghec_operations: merge_ghec_operations)
      end

      # Public: Retrieve the current Release, checking application settings.
      #
      # Returns a Release instance (or nil, if no release could be identified)
      def self.current(include_unpublished:)
        @current ||= begin
          enterprise_version = read_enterprise_release_file
          if GitHub.enterprise? && enterprise_version
            # Enterprise branches have an ENTERPRISE_RELEASE file.
            new("ghes", version: release_series_for(enterprise_version), include_unpublished: include_unpublished)
          else
            # Otherwise, it's the normal dotcom release
            new("api.github.com", version: nil, include_unpublished: include_unpublished)
          end
        end
      end

      # Internal: Read the ENTERPRISE_RELEASE file, if available.
      #
      # The ENTERPRISE_RELEASE file is present in GHES release branches.
      #
      # Returns a String representing the GHES version number (without a 'ghes-' prefix), or nil.
      def self.read_enterprise_release_file
        if (enterprise_release_path = Rails.root.join("ENTERPRISE_RELEASE")).exist?
          enterprise_release_path.read.strip
        end
      end

      def self.release_series_for(version)
        version.split(".").slice(0, 2).join(".")
      end


      attr_reader :name, :version
      def initialize(name, version: nil, include_unpublished: false, include_test_fixtures: false, merge_ghec_operations: false)
        @name = name
        @version = if version
          Gem::Version.new(self.class.release_series_for(version))
        else
          nil
        end
        @include_unpublished = include_unpublished
        @include_test_fixtures = include_test_fixtures
        @merge_ghec_operations = merge_ghec_operations
      end

      def exist?
        OpenApi.root.join("config/releases/#{identifier}.yaml").exist?
      end

      def operations
        @operations ||= find_operations(filenames: operation_filenames)
      end

      def test_fixture_operations
        @test_fixture_operations ||= find_operations(filenames: test_fixture_operations_filenames)
      end

      def webhooks
        @webhooks ||= find_webhooks(filenames: webhook_filenames)
      end

      def test_fixture_webhooks
        @test_fixture_webhooks ||= find_webhooks(filenames: test_fixture_webhooks_filenames)
      end

      def identifier
        @identifier ||= [@name, @version.to_s].map { |p| p unless p.nil? || p.strip.empty?  }.compact.join("-")
      end
      alias_method :to_s, :identifier

      def filename
        @filename ||= identifier + ".yaml"
      end

      def published?
        !!config["published"]
      end

      def deprecated?
        !!config["deprecated"]
      end

      def meets_release_constraint?(release_constraint)
        case release_constraint
        when String
          release_constraint == @name
        when Hash
          if release_constraint.size == 1
            if @version
              constraint_name, raw_requirement = release_constraint.flatten
              requirement = Gem::Requirement.create(raw_requirement)
              constraint_name == @name && requirement.satisfied_by?(@version)
            end
          else
            raise Error, "Invalid release constraint: #{release_constraint.inspect}"
          end
        end
      end

      def content
        @content ||= build_content
      end

      def write(format:, serialize_as: :json, base_path: nil, breaking_changes_scope: nil, api_version: nil, include_next_version: false, include_webhooks: false, expand_references: true)
        if (writer = self.class.writers[format])
          writer.write(
            self,
            format: serialize_as,
            base_path: base_path,
            breaking_changes_scope: breaking_changes_scope,
            api_version: api_version,
            include_next_version: include_next_version,
            include_webhooks: include_webhooks,
            expand_references: expand_references,
          )
        else
          raise Error, "Unknown format `#{format.inspect}` - must be one of #{self.class.writers.keys.inspect}"
        end
      end

      def to_h(environment: ReleaseWriter::ENV_PUBLIC, include_webhooks: false, expand_references: true)
        writer = self.class.writers.fetch(:dereferenced)
        writer.new(self, environment: environment, include_webhooks: include_webhooks, expand_references: expand_references).content
      end

      def variables
        @variables ||= config["variables"] || {}
      end

      def patch
        @patch ||= Hana::Patch.new(config["patch"] || [])
      end

      # Public: Dumps release patch configs in app/api/description/config/releases/*
      def write_config
        File.write(OpenApi.root.join("config/releases", filename), YAML.dump(config))
      end

      def config
        @config ||= begin
          patch_file = OpenApi.root.join("config/releases", filename)
          unless patch_file.exist?
            message = <<~MSG
              Could not find an OpenAPI release configuration for file `#{patch_file}`."

              This usually means you have not configured an OpenAPI release for the current enterprise version.

              More info: https://thehub.github.com/engineering/development-and-ops/public-apis/rest/openapi/enterprise/
            MSG
            raise ReleaseNotFoundError, message
          end
          YAML.load_file(patch_file)
        end
      end

      private

      def build_content
        # Load the release boilerplate
        base = YAML.safe_load(ERB.new(File.read(OpenApi.root.join("config/release.yaml"))).result)
        # Apply any release-specific JSON patch files
        description = patch.apply(base)
        # Link operations
        description["paths"] = build_paths(operations: operations).sort_by { |k, _| k }.to_h
        # Link webhooks
        webhooks = build_webhooks.to_h

        unless webhooks.empty?
          description[OpenApi.webhook_key] = webhooks
        end

        # Test fixtures
        if @include_test_fixtures
          description["paths"].merge!(build_paths(operations: test_fixture_operations).sort_by { |k, _| k }.to_h)
          description[OpenApi.webhook_key].merge(test_fixture_webhooks) if test_fixture_webhooks.any?
        end

        # Merge GHEC operations for dotcom
        if @merge_ghec_operations && @name == "api.github.com"
          description["paths"].merge!(ghec_description["paths"]).sort_by { |k, _| k }.to_h
        end

        # Return description
        description
      end

      def build_webhooks
        webhooks.sort_by(&:name).reduce({}) do |memo, webhook|
          memo[webhook.name] = { "post" => { "$ref" => webhook.filepath } }
          memo
        end
      end

      def build_paths(operations:)
        operations.sort_by(&:ref).group_by(&:http_path).reduce({}) do |memo, (http_path, path_operations)|
          method_refs = path_operations.group_by(&:http_method).reduce({}) do |path_memo, (http_method, references)|
            if references.size > 1
              filenames = references.map(&:ref)
              raise Error, "Multiple operations for release #{identifier} defined as [#{http_method} #{http_path}]: #{filenames}"
            end
            path_memo[http_method] = { "$ref" => references.first.ref.to_s }
            path_memo
          end
          memo[http_path] = method_refs.sort_by { |method, _| METHOD_ORDER.index(method) }.to_h
          memo
        end
      end

      def ghec_description
        ghec_file = OpenApi.root.join("ghec.yaml")
        unless ghec_file.exist?
          message = <<~MSG
            Could not find an OpenAPI release configuration for file `#{ghec_file}`."
          MSG
          raise ReleaseNotFoundError, message
        end
        YAML.load_file(ghec_file)
      end

      def find_operations(filenames:)
        filenames.each.with_object([]) do |operation_path, memo|
          begin
            operation_data = YAML.load_file(operation_path)
          rescue Psych::SyntaxError => e
            raise "Invalid YAML in operation #{operation_path}, #{e}"
          end

          release_constraints = operation_data.fetch("x-github-releases", nil)
          deprecated = operation_data.fetch("deprecated", nil)

          unless release_constraints || deprecated
            raise(Error, (<<~ERROR))
              The #{operation_path} is missing the x-github-releases` extension.
              This is used to determine which release this operation will be associated with.

              Example:

              x-github-releases:
                - api.github.com

              If your operation is part of a release, but is not ready to be published yet (feature flagged for example),
              use `published: false` to exclude it from documentation and our open source OpenAPI.

              x-github-internal:
                # ...
                published: false

              For more info, especially regarding now to add it to an Enterprise release
              visit: https://thehub.github.com/engineering/development-and-ops/public-apis/contributing-to-openapi/#versioning-whole-operations
            ERROR
          end

          published = !!operation_data.dig("x-github-internal", "published")
          next if (!published && !@include_unpublished) || (!release_constraints && deprecated)

          if release_constraints.any?(&method(:meets_release_constraint?))
            http_method = operation_data["x-github-http-method"] || operation_data.dig("x-github-internal", "http-method")
            http_path = operation_data["x-github-http-path"] || operation_data.dig("x-github-internal", "path")
            if http_method && http_path
              ref = operation_path.to_s[%r{/(operations/.+?\.yaml)\Z}, 1]
              memo << OperationRef.new(http_path, http_method, ref)
            end
          end
        end
      end

      def find_webhooks(filenames:)
        filenames.each.with_object([]) do |webhook_path, memo|
          begin
            webhook_data = YAML.load_file(webhook_path)
          rescue Psych::SyntaxError => e
            raise "Invalid YAML in webhook #{webhook_path}, #{e}"
          end

          webhook_name = webhook_data.dig("x-github-internal", "webhook-name")
          unless webhook_name
            raise(Error, (<<~ERROR))
              The #{webhook_path} is missing the x-github-internal/webhook-name field.
              This field denotes a required name for each webhook.

              Example:

              x-github-internal:
                # ...
                webhook-name: 'check-run-completed'
            ERROR
          end

          release_constraints = webhook_data["x-github-releases"]
          unless release_constraints
            raise(Error, (<<~ERROR))
              The #{webhook_path} is missing the x-github-releases` extension.
              This is used to determine which release this webhook will be associated with.

              Example:

              x-github-releases:
                - api.github.com

              If your webhook is part of a release, but is not ready to be published yet (feature flagged for example),
              use `published: false` to exclude it from documentation and our open source OpenAPI.

              x-github-internal:
                # ...
                published: false

              For more info, especially regarding now to add it to an Enterprise release
              visit: https://thehub.github.com/engineering/development-and-ops/public-apis/contributing-to-openapi/#versioning-whole-webhooks
            ERROR
          end

          published = !!webhook_data.dig("x-github-internal", "published")
          next if !published && !@include_unpublished

          if release_constraints.any?(&method(:meets_release_constraint?))
            ref = webhook_path.to_s[%r{/(webhooks/.+?\.yaml)\Z}, 1]
            memo << WebhookRef.new(ref, webhook_name)
          end
        end
      end

      def operation_filenames
        OpenApi.root.glob("operations/**/*.yaml")
      end

      def test_fixture_operations_filenames
        Rails.root.join("test/fixtures/open_api").glob("operations/**/*.yaml")
      end

      def webhook_filenames
        OpenApi.root.glob("webhooks/**/*.yaml")
      end

      def test_fixture_webhooks_filenames
        Rails.root.join("test/fixtures/open_api").glob("webhooks/**/*.yaml")
      end
    end
  end
end
