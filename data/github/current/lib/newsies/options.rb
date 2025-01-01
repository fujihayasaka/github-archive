# typed: false
# frozen_string_literal: true

module Newsies
  # Public: A special kind of struct used for handling arbitrary key/value
  # options.  Looks like a Hash to the caller, but is strongly typed.
  class Options < Struct
    # Public: Converts the given value into a new Options object.
    #
    # value - Either a value of this Options class, or a Hash.  Any other type
    #         of value is passed to #from_unknown, which raises by default.
    #
    # Returns an Options instance.
    def self.from(value)
      case value
      when self then value
      when Hash then fill(value)
      when nil then new
      else from_unknown(value)
      end
    end

    # Internal: Converts an unknown type of value passed to #from.  Overwrite
    # this if an Options class expects to receive other types of objects.
    #
    # value - Any ruby object that is passed to #from.
    #
    # Returns an Options instance.
    def self.from_unknown(value)
      raise NotImplementedError
    end

    # Public: Converts a Hash into an Options instance.
    #
    # hash - A Hash, or nil.
    #
    # Returns a new Options instance.
    def self.fill(hash)
      new.fill(hash)
    end

    # Public: Sets properties on this Options instance from a Hash.
    #
    # hash - A Hash, or nil.
    #
    # Returns this Options instance.
    def fill(hash)
      hash.each_pair do |key, value|
        send("#{key}=", value)
      end if hash
      self
    end

    # Public: Converts this Options instance back into a Hash based on the
    # Options members.
    #
    # Returns a Hash.
    def to_hash
      Hash[each_pair.to_a]
    end
  end
end
