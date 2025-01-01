# typed: false
# frozen_string_literal: true

require "json"
require "active_support"

module OpenApi
  module Description
    class BundledReleaseWriter < ReleaseWriter

      def path(format: :json)
        @base_path.join(
          "generated",
          File.basename(@release.filename, ".yaml"),
          File.basename(@release.filename, ".yaml") << file_extension(format)
        )
      end

      def content
        return @content if defined?(@content)
        @content = Marshal.load(Marshal.dump(@release.content))

        source_path = OpenApi.root.join(@release.filename)
        assigning_components do
          expand(@content, source_path)
        end

        OpenApi::Description::Expander.replace_variables(@content, @release)

        if @environment == OpenApi::Description::ReleaseWriter::ENV_PUBLIC
          filter!(@content)
        end

        unless @include_webhooks
          filter_webhooks!(@content)
        end

        # Ensure all refs are published, at this point anything that is unpublished
        # should have been filtered out. If not, it is an error.
        @components.each do |k, v|
          if v.is_a?(Hash) && v.key?("x-unpublished")
            raise ArgumentError, "A published operation references a $ref component #{k.inspect} in #{source_path} that is unpublished"
          end
        end

        @content
      end

      def assigning_components(&block)
        @components = {}
        yield
        # Insert components inline
        @content["components"] ||= {}
        @content["components"].deep_merge!(@components)

        # Webhook components live in a subdirectory but we can't have any subschemas
        # in components according to the OpenAPI meta-schema, so we are moving the webhook
        # components back to the top level here.
        return unless @content["components"]["schemas"]
        webhooks_schemas = @content["components"]["schemas"].delete("webhooks") || {}
        webhooks_schemas.transform_keys! { |k| "webhook-#{k}" }
        @content["components"]["schemas"].merge!(webhooks_schemas)
      end

      def serialize(content, format:)
        if format == :json
          JSON.pretty_generate(content)
        elsif format == :yaml
          YAML.dump(content)
        else
          raise ArgumentError, "Unhandled format #{format}"
        end
      end

      private

      # Private: Recursively expand operation $ref values in a datastructure, relative to a path,
      #          stripping any disallowed extended properties, and moving any component $refs to
      #          inline components.
      #
      # value - The data
      # source_path - a Pathname of the source file, used to resolve relative references
      #
      # Modifications are made in-place.
      def expand(value, source_path)
        # Expand
        case value
        when Hash
          OpenApi::Description::Overlay.apply(value, @release)
          OpenApi::Description::BreakingChanges.apply(value, release: @release, api_version: @api_version, scope: @breaking_changes_scope, include_next: @include_next_version)
          # according to the RFC, $ref resolution should only happen
          # when the value of the $ref is a "JSON string value".
          #
          # https://tools.ietf.org/html/draft-pbryan-zyp-json-ref-03#section-3
          #
          # Therefore, any $ref keys that aren't a string can be considered
          # as a $ref literal, and expanded as any other value would be.
          if value.key?("$ref") && value["$ref"].is_a?(String)
            # don't try to expand examples with $ref keys, they should be
            # considered literal.
            return value if source_path.to_s.include?("components/examples")

            if err = OpenApi::Description::Expander.check_for_invalid_ref(value, value["$ref"])
              raise "#{err} (found: #{value.inspect}) in #{source_path}"
            end

            # Mark this file as expanded for any subsequent expansions
            ref_target = value.delete("$ref")
            nullable = !!value.delete("x-nullable-ref")

            if ref_target.start_with?("#")
              raise ArgumentError, "Inline components not supported: #{ref_target}"
            else
              ref_path = source_path.dirname.join(ref_target)
              if ref_path.exist?
                # Convert to absolute; remove .., etc
                ref_path = ref_path.realpath
                if ref_path.to_s.include?("/x-previews/")
                  ref_value = YAML.load_file(ref_path)
                elsif ref_path.to_s.include?("/components/")
                  ref_value = expand_component(ref_path, nullable: nullable)
                else
                  ref_value = expand_operation(ref_path)
                end
                value.merge!(ref_value)
              else
                raise ArgumentError, "Bad $ref #{ref_target.inspect} from #{source_path}"
              end
            end
          else
            value.each do |_k, v|
              expand(v, source_path)
            end
          end
        when Array
          value.each { |v| expand(v, source_path) }
        else
          value
        end
      end

      # Private: Expand a component, assign it as an inline component, and
      #          change the reference accordingly.
      #
      # ref_path - the Pathname pointing to the component
      # nullabe  - Adds nullable to the component
      #
      # Returns a Hash with the updated (inline component) ref.
      def expand_component(ref_path, nullable: false)
        address = ref_path.to_s.
          sub(%r{\A.*?/components/}, "").
          sub(%r{\..*?\Z}, "").
          split("/")

        if nullable
          address = address[0..-2].concat(["nullable-#{address.last}"])
        end

        unless @components.dig(*address)
          # Haven't saved component, need to assign
          ref_value = YAML.load_file(ref_path)

          # Create a nullable version of the component. This
          # is a workaround for the fact OpenAPI does not support "nullable refs"
          if nullable
            ref_value["nullable"] = true
          end

          expand(ref_value, ref_path)
          assign_component(ref_value, address)
        end

        # Webhook components don't match the file path, so we need to
        # update them to #/components/schemas/webhook-{event-name}
        if address.first(2) == %w[schemas webhooks]
          path = File.join("#/components", "schemas", "webhook-#{address.last}")
        else
          path = File.join("#/components", *address)
        end
        { "$ref" => path }
      end

      # Private: Expand a reference to an operation
      #
      # ref_path - the Pathname pointing to the operation
      #
      # Returns a Hash with the operation contents.
      def expand_operation(ref_path)
        ref_value = YAML.load_file(ref_path)
        expand(ref_value, ref_path)
        ref_value
      end

      # Private: Assign component contents to a component address.
      #
      # - content - a Hash
      # - address - an Array of String values
      def assign_component(content, address)
        target = @components
        address.each do |element|
          target = target[element] ||= {}
        end
        target.replace(content)
      end

      # Private: Construct file extension for output
      #
      # - format - extension [json, yaml]
      def file_extension(format)
        ["", @api_version, format].compact.join(".")
      end
    end
  end
end
