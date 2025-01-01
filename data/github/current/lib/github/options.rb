# typed: true
# frozen_string_literal: true

module GitHub
  class Options < Struct
    # Gracefully create an instance from Hash
    # or instance of SerializerOptions
    #
    # value - Hash, SerializerOptions, or nil
    #
    # Returns - SerializerOptions
    def self.from(value)
      case value
      when self then value
      when Hash then fill(value)
      when nil then new
      else from_unknown(value)
      end
    end

    def self.from_unknown(value)
      raise ArgumentError, "Unknown: value of type #{value.class}"
    end

    # Create SerializerOptions instance and map
    # struct members to values in a Hash
    #
    # hash - Options hash
    #
    # Returns - SerializerOptions
    def self.fill(hash)
      new.fill(hash)
    end

    # Map struct members to values in a Hash
    #
    # hash - Options hash
    #
    # Returns - SerializerOptions
    def fill(hash)
      hash.each_pair do |key, value|
        send("#{key}=", value)
      end if hash
      self
    end

    alias update fill

    def merge(hash)
      dup.fill(hash)
    end
  end
end
