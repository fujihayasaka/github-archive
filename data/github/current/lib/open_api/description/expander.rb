# typed: true
# frozen_string_literal: true

module OpenApi
  module Description
    class Expander

      class Error < StandardError; end

      def self.global_ref_caches
        @global_ref_caches ||= {}
      end

      def self.global_ref_cache(release, api_version, scope, include_next)
        global_ref_caches[[release, api_version, scope, include_next]] ||= {}
      end

      # Private: Recursively expand $ref values in a datastructure, relative to a path,
      #          stripping any disallowed extended properties.
      #
      # value - The data
      # source_path - a Pathname of the source file, used to resolve relative references
      # parent - The parent object, used to resolve relative references
      # parent_key - The key that points to the value in the parent object
      #
      #
      # Modifications are made in-place.
      def self.expand(value, source_path, parent: nil, parent_key: nil, release: OpenApi.release, api_version: nil, scope: nil, include_next: nil, ref_cache: nil)
        ref_cache ||= self.global_ref_cache(release, api_version, scope, include_next)

        case value
        when Hash
          OpenApi::Description::Overlay.apply(value, release)
          OpenApi::Description::BreakingChanges.apply(value, api_version: api_version, scope: scope, include_next: include_next, release: release)

          # do not keep discriminators or mappings in dereferenced specifications
          # discriminators only work with schema references
          if value.key?("discriminator") && value["discriminator"].key?("mapping")
            value.delete("discriminator")
          end

          # according to the RFC, $ref resolution should only happen
          # when the value of the $ref is a "JSON string value".
          #
          # https://tools.ietf.org/html/draft-pbryan-zyp-json-ref-03#section-3
          #
          # Therefore, any $ref keys that aren't a string can be considered
          # as a $ref literal, and expanded as any other value would be.
          if (ref_target = value["$ref"]) && ref_target.is_a?(String)
            if source_path.to_s.include?("components/examples")
              # don't try to expand examples with $ref keys, they should be
              # considered literal.
              final_value = value
            elsif err = check_for_invalid_ref(value, ref_target)
              raise "#{err} (found: #{value.inspect})"
            elsif ref_target.start_with?("#")
              raise Error, "Inline components not supported: #{ref_target}"
            else
              # Account for any test fixtures that may have been added.
              if GitHub.openapi_include_test_fixtures? && File.exist?(Rails.root.join("test", "fixtures", "open_api", ref_target))
                ref_path = Rails.root.join("test", "fixtures", "open_api", ref_target)
              else
                # Take the directory of the current file and tack the ref target onto it.)
                ref_path = File.expand_path(File.join(source_path, "../#{ref_target}"))
              end

              ref_value = ref_cache[ref_path] ||= begin
                # Expand _before_ caching, then we don't have to re-expand later.
                unexpanded_yaml = YAML.load_file(ref_path)
                expand(unexpanded_yaml, ref_path, release: release, ref_cache: ref_cache, api_version: api_version, scope: scope, include_next: include_next)
              rescue Errno::ENOENT
                raise Error, "Bad $ref #{ref_target.inspect} from #{source_path}"
              rescue Psych::SyntaxError => e
                raise "Error parsing #{ref_path}: #{e.message}"
              end

              if ref_value.is_a?(Array) && value.has_key?("x-nullable-ref")
                raise Error, "Cannot set x-nullable-ref when the expanded $ref value is an array"
              end

              nullable = !!value["x-nullable-ref"]
              if OpenApi.version == OpenApi::NEXT_VERSION
                ref_value["type"] = Array(ref_value["type"]) << "null" if nullable
                final_value = ref_value
              else
                final_value = nullable ? ref_value.merge({ "nullable" => true }) : ref_value
              end

            end

            # overwrite the ref value with the expanded value
            # sometimes parent is a hash and parent_key is a string key
            # sometimes parent is an array and parent_key is an index number
            parent[parent_key] = final_value if parent
          else
            value.each do |k, v|
              expand(v, source_path, parent: value, parent_key: k, release: release, ref_cache: ref_cache, api_version: api_version, scope: scope, include_next: include_next)
            end
          end
        when Array
          value.each_with_index { |v, i| expand(v, source_path, parent: value, parent_key: i, release: release, ref_cache: ref_cache, api_version: api_version, scope: scope, include_next: include_next) }
        when String
          # replace the variables here to avoid a second iteration over the whole schema
          replace_variables(value, release)
        else
          value
        end
      end

      def self.deep_freeze(value)
        return value if value.frozen?

        case value
        when Array
          value.map! { |x| deep_freeze(x) }
          value.freeze
        when Hash
          value.transform_values! { |x| deep_freeze(x) }
          value.freeze
        when String
          -value
        else
          value
        end
      end

      def self.check_for_invalid_ref(value, ref)
        return nil if value.size == 1

        if ref.include?("components/x-previews")
          if value.keys.sort != ["$ref", "required"]
            return "When a $ref is present for an x-preview, the only other key allowed is 'required'"
          else
            return nil
          end
        end

        if OpenApi.version == OpenApi::NEXT_VERSION && !OpenApi.performing_transform?
          return "x-nullable-ref is unsupported in OpenAPI 3.1." if value.key?("x-nullable-ref")

          unless value.keys.sort == ["$ref", "description", "summary"] || value.keys.sort == ["$ref", "description"] || value.keys.sort == ["$ref", "summary"]
            return "The only allowed keys when a $ref is present are: '$ref', 'description', and 'summary'"
          end
        else
          # handles the case when the component isn't nullable, but has more than 1 key.
          return "When a $ref is present, it is the only allowed key." if !value.key?("x-nullable-ref")

          # handles the case when it is nullable (2 keys assumed in this case)
          # but there are _more_ than 2 keys found.
          return "When a $ref is present, it is the only allowed key." if value.size > 2 && value.key?("x-nullable-ref")
        end

        nil
      end

      # Recursively replaces variables ${var} in place
      def self.replace_variables(value, release)
        if value.is_a?(Hash)
          value.each do |_key, v|
            replace_variables(v, release)
          end
        elsif value.is_a?(Array)
          value.each { |v| replace_variables(v, release) }
        elsif value.is_a?(String)
          value.gsub!(/\${\w+}/) do |match|
            var_name = match[2..-2]
            variable_value = release.variables[var_name]
            if variable_value.nil?
              raise "Release must configure variable #{var_name}"
            end
            variable_value
          end
        end
      end
    end
  end
end
