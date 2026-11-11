# typed: true
# frozen_string_literal: true

module Arvore
  class PathString
    class Base16Encoder
      # Receives a Integer and returns the string base16 version of it.
      def self.encode(n)
        n.to_s(16)
      end

      # Receives a String and returns the integer representation of that
      # hexedecimal string.
      def self.decode(hex_n)
        hex_n.hex
      end
    end

    class NullEncoder
      def self.encode(n); n; end
      def self.decode(n); n; end
    end

    def initialize(path = nil, encoder: Base16Encoder, delimiter: "/")
      @s = path ? path.dup : ""
      @delimiter = delimiter
      @encoder = encoder ? encoder : NullEncoder
    end

    # Append a new decoded id to the string
    def append(id)
      if @s.size != 0
        @s += @delimiter
      end
      @s += @encoder.encode(id)
    end

    # Append the give string.
    # There will be no encoding applied
    def raw_append(s)
      if @s.size != 0
        @s += @delimiter
      end
      @s += s
    end

    def to_s
      @s
    end

    # Returns the number of levels the path has
    def depth
      @s.count(@delimiter)
    end

    # Yields the block with every decoded id.
    def each_id
      @s.split(@delimiter).each do |hex_id|
        yield @encoder.decode(hex_id)
      end
    end

    # Returns the immediate decoded parent id
    def parent_id
      if s = @s.split(@delimiter)[-2]
        @encoder.decode(s)
      end
    end

    # Returns the decoded id
    def id
      if s = @s.split(@delimiter)[-1]
        @encoder.decode(s)
      end
    end

    # Checks if a given id is in the path already.
    # This can be used to check cycle references on the tree.
    def include?(id)
      return false unless id
      encoded_id = @encoder.encode(id)
      @s == encoded_id ||
        @s.start_with?("#{encoded_id}#{@delimiter}") ||
        @s.ends_with?("#{@delimiter}#{encoded_id}") ||
        @s.include?("#{@delimiter}#{encoded_id}#{@delimiter}")
    end
  end
end
