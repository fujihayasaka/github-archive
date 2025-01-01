# typed: true
# frozen_string_literal: true

module Actions
  module YamlParsing
    # Helper for comparing two YAML objects and generating human-readable differences
    class DiffHelper
      # Compare two YAML objects and return a string describing the first difference
      # @param obj1 [Object] First YAML object or exception
      # @param obj2 [Object] Second YAML object or exception
      # @return [String, nil] Human readable difference or nil if objects are equal
      def self.compare(obj1, obj2)
        result = compare_recursive(obj1, obj2, "")

        # Truncate after 1000 characters
        if result && result.length > 1000
          result = "#{result[0..999]}[truncated]"
        end
        result
      end

      # Recursively compare two YAML objects and return a string describing the first difference
      # @param obj1 [Object] First YAML object or exception
      # @param obj2 [Object] Second YAML object or exception
      # @param path [String] Current path in the object (used for recursion)
      # @return [String, nil] Human readable difference or nil if objects are equal
      private_class_method def self.compare_recursive(obj1, obj2, path)
        # Exception?
        if obj1.is_a?(Exception) && obj2.is_a?(Exception)
          if obj1.message == obj2.message && obj1.class == obj2.class
            return nil
          end

          if obj1.message == obj2.message && obj1.is_a?(Psych::SyntaxError) && obj2.is_a?(Actions::YamlParsing::UserError)
            return nil
          end

          return "Both YAML objects failed to parse with different errors: '(#{obj1.class}) #{obj1.message}' vs '(#{obj2.class}) #{obj2.message}'"
        elsif obj1.is_a?(Exception)
          return "First YAML object failed to parse with error: '(#{obj1.class}) #{obj1.message}'"
        elsif obj2.is_a?(Exception)
          return "Second YAML object failed to parse with error: '(#{obj2.class}) #{obj2.message}'"
        end

        # Type mismatch?
        if obj1.class != obj2.class
          return "Type mismatch (#{obj1.class} vs #{obj2.class}) at path '#{path}'"
        end

        case obj1
        when Hash
          obj1.each do |key, value|
            # Key not in obj2?
            if !obj2.key?(key)
              return "Path '#{path_with_key(path, key)}' exists in first object but not in second"
            end

            # Recurse
            diff = compare_recursive(value, obj2[key], path_with_key(path, key))
            if diff
              return diff
            end
          end

          obj2.keys.each do |key|
            # Key not in obj1?
            if !obj1.key?(key)
              return "Path '#{path_with_key(path, key)}' exists in second object but not in first"
            end
          end

        when Array
          # Length mismatch?
          if obj1.length != obj2.length
            return "Array length mismatch (#{obj1.length} vs #{obj2.length}) at path '#{path}'"
          end

          # Recurse
          obj1.each_with_index do |item, index|
            diff = compare_recursive(item, obj2[index], "#{path}[#{index}]")
            return diff if diff
          end

        else
          # Scalar mismatch?
          if obj1 != obj2
            return "Value mismatch at path '#{path}'"
          end
        end

        # No differences found
        nil
      end

      # Generate path string with key
      # @param path [String] Current path
      # @param key [String, Symbol] Key to append
      # @return [String] Updated path
      private_class_method def self.path_with_key(path, key)
        path.empty? ? key.to_s : "#{path}.#{key}"
      end
    end
  end
end
