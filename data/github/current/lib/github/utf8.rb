# typed: true
# frozen_string_literal: true

require "github/encoding"

module GitHub
  # Mixin that adds a simple utf8() helper method. Use this to massage data
  # stored as binary before crossing a utf8 only boundary.
  module UTF8
    # Detect encoding and transcode to utf8.
    #
    # string - A possibly non-utf8 string.
    #
    # Returns a string that's guaranteed to be valid utf8 encoded character
    # data. Invalid character sequences are converted to question marks. If the
    # input string is nil, nil will be returned.
    def utf8(string)
      return if string.nil?
      GitHub::Encoding.try_guess_and_transcode(string)
    end

    # Scrub invalid unicode3 characters from a string.
    #
    # string - A possibly non-unicode3 string (characters over 0xFFFF).
    #
    # Returns a UTF-8 copy of the string where any characters over 0xFFFF
    # are removed.
    def self.scrubbed_unicode3(string)
      return if string.nil?
      string.dup.each_codepoint.filter { |c| c <= 0xFFFF }.pack("U*")
    end

    def self.valid_unicode3?(string)
      return true if string.ascii_only?
      string.encoding == ::Encoding::UTF_8 &&
        string.valid_encoding? &&
        string.each_codepoint.all? { |c| c <= 0xFFFF }
    end

    def self.valid_email?(string)
      return unless string

      return true if string.ascii_only?
      unless string.encoding == ::Encoding::UTF_8
        string = string.dup.force_encoding(::Encoding::UTF_8)
      end
      string.valid_encoding? && string.each_codepoint.all? { |c| c <= 0xFFFF }
    end
  end
end
