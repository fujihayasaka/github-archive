# typed: true
# frozen_string_literal: true

# Class for matching a single Condition pair (attribute_name / Regexp)
# against a target object.
module Spam
  class Condition
    attr_accessor :property, :pattern

    def initialize(options)
      if options.is_a? String
        options = JSON.parse options
      end
      options = HashWithIndifferentAccess.new(options || {})
      @property = options["attribute_name"] || options["property"]
      @pattern        = options["pattern"]
    end

    def matches?(target)
      if has_actual_attribute? target
        regexp =~ target.attributes[property]
      elsif has_allowed_method?(target)
        regexp =~ target.send(property)
      end
    end

    # Return true if this is an actual attribute belonging to target's
    # class, not just a method to which target will respond.
    # Return false otherwise.
    def has_actual_attribute?(target)
      target.respond_to?(:attributes) &&
        target.attributes.include?(property)
    end

    def has_allowed_method?(target)
      allowed_methods = target.class.instance_methods -
                        ActiveRecord::Base.instance_methods
      allowed_methods.include? property.to_sym
    end

    def =~(target)
      regexp =~ target
    end

    def regexp
      @regexp ||= Regexp.new(pattern)
    end

    def dump_as_hash
      {
        pattern: pattern,
        property: property,
      }
    end

    def dump_to_json
      dump_as_hash.to_json
    end
  end # class  Condition
end   # module Spam
