# typed: true
# frozen_string_literal: true

module Coders
  # Generic handler for encoding/decoding (i.e. serialization) of ActiveRecord attributes.
  class Handler
    def self.accessors_for(coder)
      members = coder.members
      (members + members.map { |member| "#{member}=".to_sym }).sort
    end

    def initialize(coder, compressor: GitHub::ZSON)
      @coder = coder
      @compressor = compressor
    end

    def dump(data)
      if data.is_a?(String)
        data.b
      else
        compressor.encode data.to_h
      end
    end

    def load(data)
      coder.new compressor.decode(data).symbolize_keys
    end

    private

    attr_reader :coder, :compressor
  end
end
