# typed: true
# frozen_string_literal: true

require "set"

module OpenApi
  module Description
    # Resolves changeset names to the API endpoints they affect by scanning
    # x-github-breaking-changes annotations and tracing $ref dependencies
    # from component files back to operations.
    class EndpointResolver
      REF_PATTERN = /['"]?\$ref['"]?:\s*['"]?(\S+?\.yaml)['"]?/
      BREAKING_KEY = "x-github-breaking-changes"

      # Build a mapping of changeset names to affected endpoint strings.
      #
      # @return [Hash{String => Array<String>}] e.g. { "remove_has_downloads" => ["GET /repos/{owner}/{repo}", ...] }
      def self.resolve_all
        new.resolve_all
      end

      def resolve_all
        changeset_to_files = scan_breaking_change_annotations
        ref_index = build_reverse_ref_index

        changeset_to_files.each_with_object({}) do |(changeset_name, files), result|
          endpoints = files.flat_map { |file| resolve_to_endpoints(file, ref_index) }.uniq.sort
          result[changeset_name] = endpoints unless endpoints.empty?
        end
      end

      private

      # Scan all YAML files for x-github-breaking-changes and map changeset names to file paths.
      def scan_breaking_change_annotations
        changeset_files = Hash.new { |h, k| h[k] = [] }

        yaml_files_outside_changesets.each do |file|
          content = File.read(file)
          next unless content.include?(BREAKING_KEY)

          parsed = YAML.safe_load(content)
          next unless parsed.is_a?(Hash) && parsed[BREAKING_KEY]

          parsed[BREAKING_KEY].each do |change|
            changeset_files[change["changeset"]] << file.to_s
          end
        end

        changeset_files
      end

      # Build a reverse index: component file path => [operation file paths that reference it].
      # Handles transitive references (operation → schema A → schema B).
      def build_reverse_ref_index
        # Forward index: file => set of files it directly references
        forward = Hash.new { |h, k| h[k] = Set.new }

        all_yaml_files.each do |file|
          dir = File.dirname(file)
          File.foreach(file) do |line|
            if (match = line.match(REF_PATTERN))
              resolved = File.expand_path(File.join(dir, match[1]))
              forward[file.to_s].add(resolved) if File.exist?(resolved)
            end
          end
        end

        # Reverse index: referenced file => set of files that reference it
        reverse = Hash.new { |h, k| h[k] = Set.new }
        forward.each do |source, targets|
          targets.each { |target| reverse[target].add(source) }
        end

        reverse
      end

      # Given a file path, resolve it to endpoint strings ("METHOD /path").
      # If the file is an operation, extract the endpoint directly.
      # If it's a component, walk the reverse ref index to find all operations.
      def resolve_to_endpoints(file, ref_index)
        if operation_file?(file)
          endpoint = extract_endpoint(file)
          endpoint ? [endpoint] : []
        else
          find_ancestor_operations(file, ref_index).filter_map { |op_file| extract_endpoint(op_file) }
        end
      end

      # Walk the reverse ref index transitively to find all operation files that
      # ultimately reference the given component file.
      def find_ancestor_operations(file, ref_index, visited = Set.new)
        return [] if visited.include?(file)
        visited.add(file)

        operations = []
        ref_index[file]&.each do |referrer|
          if operation_file?(referrer)
            operations << referrer
          else
            operations.concat(find_ancestor_operations(referrer, ref_index, visited))
          end
        end
        operations
      end

      def operation_file?(file)
        file.include?("/operations/")
      end

      # Extract "METHOD /path" from an operation file's x-github-internal field.
      # Skips unpublished operations so they don't appear in public changelogs.
      def extract_endpoint(file)
        parsed = YAML.safe_load(File.read(file))
        return nil unless parsed.is_a?(Hash)

        internal_extension_block = parsed["x-github-internal"]
        return nil unless internal_extension_block

        return nil if internal_extension_block["published"] == false

        http_method = internal_extension_block["http-method"]
        path = internal_extension_block["path"]
        return nil unless http_method && path

        "#{http_method.upcase} #{path}"
      end

      def yaml_files_outside_changesets
        all_yaml_files.reject { |f| f.to_s.include?("/changesets/") || f.to_s.include?("/changelogs/") }
      end

      def all_yaml_files
        @all_yaml_files ||= OpenApi.root.glob("**/*.yaml")
      end
    end
  end
end
