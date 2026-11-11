# typed: true
# frozen_string_literal: true

module ConfigValidator
  class Validation
    attr_reader :errors

    def initialize(validation_schema)
      @validation_schema = ActiveSupport::HashWithIndifferentAccess.new(validation_schema)
      @errors = {}
    end

    def validate!(schema)
      schema = ActiveSupport::HashWithIndifferentAccess.new(schema)
      validate_hash(validation: @validation_schema, key: nil, schema: schema)
      @errors.empty?
    end

    def valid?
      @errors.empty?
    end

    private

    def validate_hash(validation:, key:, schema:)
      validation.each do |sub_key, sub_validation|
        validate_entry(
          validation: sub_validation,
          key: [key, sub_key].compact.join("."),
          schema: schema[sub_key]
        )
      end
    end

    def validate_array(validation:, key:, schema:)
      if schema.is_a?(Array)
        schema.each do |sub_schema|
          validate_entry(
            validation: validation.first, # TODO: Why first?
            key: "#{key}.entry",
            schema: sub_schema
          )
        end
      end
    end

    def validate_entry(validation:, key:, schema:)
      check_length(validation: validation, key: key, schema: schema)
      check_depth(validation: validation, key: key, schema: schema)
      check_required(validation: validation, key: key, schema: schema)
      check_type(validation: validation, key: key, schema: schema)
      check_enum(validation: validation, key: key, schema: schema)
      check_match(validation: validation, key: key, schema: schema)

      validation_entry = validation[:entry]
      case validation_entry
      when Array
        validate_array(validation: validation_entry, key: key, schema: schema) if schema
      when Hash
        validate_hash(validation: validation_entry, key: key, schema: schema) if schema
      when nil
        # Nothing, we're done
      else
        raise "invalid entry #{validation_entry}"
      end
    end

    ##
    ## Validators
    ##

    # Fails validation if length is more than specified, or we can't respond to length
    def check_length(validation:, key:, schema:)
      return false unless validation[:length] && schema

      case schema
      when Hash, Array
        return false unless schema.length > validation[:length]
        error!(
          key,
          "cannot have more than #{validation[:length]} "\
          "#{'element'.pluralize(validation[:length])}, "\
          "but has #{schema.length} #{'element'.pluralize(schema.length)}"
        )
      when String
        return false unless schema.length > validation[:length]
        error!(
          key,
          "cannot be longer than #{validation[:length]} "\
          "#{'character'.pluralize(validation[:length])}, but was #{schema.length} in length"
        )
      else
        error!(
          key,
          "cannot validate length on an object of type #{schema.class}. "\
          "Tried to validate length of #{validation[:length]}"
        )
      end

      true
    end

    # Fails validation if depth of nestable types is more than specified
    def check_depth(validation:, key:, schema:)
      return false unless validation[:depth] && schema

      case schema
      when Hash, Array
        depth, path = max_depth(schema)
        return false unless depth > validation[:depth]
        error!(
          key,
          "cannot have a depth of more than #{validation[:depth]} "\
          "but #{key} has a nested depth of #{depth} along path #{key}#{path}"
        )
      else
        error!(
          key,
          "cannot validate depth on an object of type #{schema.class}. "\
          "Tried to validate depth of #{validation[:length]}"
        )
      end

      true
    end

    # Fails validation if required and the value is nil
    def check_required(validation:, key:, schema:)
      return false unless validation[:required] && schema.nil?

      error! key, "was required"
      true
    end

    # Fails validation if the value is not of the "type" class
    def check_type(validation:, key:, schema:)
      return false if !validation[:required] && schema.nil? # Optional and not here, dont check
      return false unless validation[:class_name]
      if validation[:class_name] == "Boolean"
        return false if schema.is_a?(TrueClass) || schema.is_a?(FalseClass) || schema.nil?
      else
        return false if schema.is_a?(validation[:class_name]) || schema.nil?
      end

      error! key, "supposed to be a #{validation[:class_name]} but was #{schema.class}"
      true
    end

    # Fails validation if the value is not in values
    def check_enum(validation:, key:, schema:)
      return false if !validation[:required] && schema.nil? # Optional and not here, dont check
      return false unless validation[:values]
      return false if validation[:values].include?(schema)

      schema = "nothing" if schema.nil?
      error! key, "must be one of #{validation[:values].join(", ")}, but was #{schema}"
      true
    end

    MATCH_REGEX = {
      ip: /\A(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\z/,
      host: /\A(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])\z/,
    }

    # Fails validation if the value does not match "matches"
    def check_match(validation:, key:, schema:)
      return false if !validation[:required] && schema.nil? # Optional and not here, dont check
      return false unless validation[:matches]

      matchers = [validation[:matches]].flatten
      return false if matchers.any? { |r| schema =~ MATCH_REGEX[r] }

      error! key, "must match a regex for one of (#{matchers.join(", ")}), but #{schema} did not"
      true
    end

    ##
    ## Helpers
    ##

    def error!(key, msg)
      @errors[key] ||= []
      @errors[key] << msg
    end

    def max_depth(node)
      # Nil node has 0 depth.
      return [0, ""] if node.nil?

      depths = case node
      when Array
        node.map.with_index do |el, idx|
          next unless el.is_a?(Hash) || el.is_a?(Array)
          depth, path = max_depth(el)
          [depth, "[#{idx}]#{path}"]
        end.compact
      when Hash
        node.map do |key, el|
          next unless el.is_a?(Hash) || el.is_a?(Array)
          depth, path = max_depth(el)
          [depth, ".#{key}#{path}"]
        end.compact
      end

      # If we are empty, we are at a terminal. This is the same level that we already counted so return 0
      return [1, ""] if depths.empty?

      # Otherwise, return the deepest branch, increased by 1 for this level
      max, path = depths.max_by(&:first)
      [max + 1, path]
    end
  end
end
