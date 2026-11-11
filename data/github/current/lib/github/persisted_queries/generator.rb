# typed: true
# frozen_string_literal: true

require "digest"
require "graphql"

module GitHub
  module PersistedQueries
    class Generator
      ParsedDocument = Struct.new(:relative_path, :operation, keyword_init: true)

      attr_reader :errors

      # glob_pattern - The glob pattern to find .graphql files
      # root_path - The root path to strip from absolute paths for relative paths
      # serviceowners - An object responding to `service_for_path(path)`, or nil to skip owner lookup
      # schema - A GraphQL::Schema instance to validate queries against, or nil to skip validation
      def initialize(glob_pattern:, root_path:, serviceowners: nil, schema: nil)
        @glob_pattern = glob_pattern
        @root_path = root_path
        @serviceowners = serviceowners
        @schema = schema
        @errors = []
      end

      # Returns a Hash of { hash => { "name" => ..., "query" => ..., "owner" => ..., "source_file" => ... } }
      # Populates @errors with any issues found.
      def generate
        query_manifest = {}
        seen_names = {}
        fragment_registry = {}
        parsed_documents = []

        Dir.glob(@glob_pattern).sort.each do |absolute_path|
          relative_path = absolute_path.sub("#{@root_path}/", "")
          source = File.read(absolute_path)

          begin
            doc = GraphQL.parse(source)
          rescue GraphQL::ParseError => e
            @errors << "#{relative_path}: parse error — #{e.message}"
            next
          end

          operations = doc.definitions.grep(GraphQL::Language::Nodes::OperationDefinition)
          fragments = doc.definitions.grep(GraphQL::Language::Nodes::FragmentDefinition)

          if operations.size > 1
            @errors << "#{relative_path}: found #{operations.size} operations — each .graphql file must contain exactly one operation"
            next
          end

          if operations.empty? && fragments.empty?
            @errors << "#{relative_path}: no operation or fragment definition found"
            next
          end

          fragments.each do |fragment|
            next unless register_fragment(fragment_registry, fragment, relative_path)
          end

          next if operations.empty?

          operation = operations.first
          unless operation.name && !operation.name.empty?
            @errors << "#{relative_path}: missing operation name — all .graphql files must use named operations"
            next
          end

          name = operation.name

          if seen_names.key?(name)
            @errors << "Duplicate operation name '#{name}' in:\n  - #{seen_names[name]}\n  - #{relative_path}"
            next
          end
          seen_names[name] = relative_path

          parsed_documents << ParsedDocument.new(
            relative_path: relative_path,
            operation: operation,
          )
        end

        parsed_documents.each do |parsed_document|
          begin
            resolved_document = resolved_document(parsed_document.operation, fragment_registry)
          rescue KeyError => e
            @errors << "#{parsed_document.relative_path}: missing fragment definition for #{e.message.inspect}"
            next
          end

          # Validate against schema if provided
          if @schema
            query_result = @schema.validate(resolved_document)
            unless query_result.empty?
              messages = query_result.map(&:message).join("; ")
              @errors << "#{parsed_document.relative_path}: schema validation failed — #{messages}"
              next
            end
          end

          printed = GraphQL::Language::Printer.new.print(resolved_document)
          hash = Digest::SHA256.hexdigest(printed)

          owner = @serviceowners&.service_for_path(parsed_document.relative_path)&.to_s

          if @serviceowners && owner.nil?
            @errors << "#{parsed_document.relative_path}: no service owner found. " \
              "Ensure the file has an entry in SERVICEOWNERS, then run " \
              "`bin/generate-service-files.rb --cache-only` to regenerate the serviceowners cache."
            next
          end

          query_manifest[hash] = {
            "name" => parsed_document.operation.name,
            "query" => printed,
            "owner" => owner,
            "source_file" => parsed_document.relative_path,
          }
        end

        query_manifest
      end

      # Builds a name-to-hash mapping from a query manifest
      def self.name_to_hash(query_manifest)
        query_manifest.each_with_object({}) do |(hash, entry), map|
          map[entry["name"]] = hash
        end
      end

      private

      def register_fragment(fragment_registry, fragment, relative_path)
        name = fragment.name

        if fragment_registry.key?(name)
          @errors << "Duplicate fragment name '#{name}' in:\n  - #{fragment_registry[name][:source_file]}\n  - #{relative_path}"
          return false
        end

        fragment_registry[name] = {
          node: fragment,
          source_file: relative_path,
        }
      end

      def resolved_document(operation, fragment_registry)
        resolved_fragments = []
        seen_fragments = {}

        collect_fragments(operation, fragment_registry, resolved_fragments, seen_fragments)

        GraphQL::Language::Nodes::Document.new(definitions: [operation, *resolved_fragments])
      end

      def collect_fragments(node, fragment_registry, resolved_fragments, seen_fragments)
        fragment_spread_names(node).each do |fragment_name|
          next if seen_fragments[fragment_name]

          fragment_entry = fragment_registry.fetch(fragment_name) do
            raise KeyError, fragment_name
          end
          fragment = fragment_entry[:node]

          seen_fragments[fragment_name] = true
          collect_fragments(fragment, fragment_registry, resolved_fragments, seen_fragments)
          resolved_fragments << fragment
        end
      end

      def fragment_spread_names(node)
        return [] unless node.respond_to?(:selections)

        node.selections.each_with_object([]) do |selection, names|
          names << selection.name if selection.is_a?(GraphQL::Language::Nodes::FragmentSpread)
          names.concat(fragment_spread_names(selection))
        end
      end
    end
  end
end
