# typed: true
# frozen_string_literal: true

# Ruby 2.7 has deprecated `URI.encode`/`URI.escape`, but we depended on that behavior.
# In order to maintain compatibility, let's import that behavior to our own app.
#
# Inspired by the implementation of CGI escape (https://ruby-doc.org/stdlib-2.7.0/libdoc/cgi/rdoc/CGI/Util.html#method-i-escape)
#
module Api::LegacyEncode
  # @param string [String] A value to escape for use in a URI
  # @param replace_pattern [Regexp] A pattern to test against `string` to find characters to replace
  # @return [String]
  def self.encode(string, replace_pattern = URI::UNSAFE)
    result = string.b.gsub(replace_pattern) do |m|
      "%#{m.unpack("H2" * m.bytesize).join("%").upcase}"
    end
    result.force_encoding("US-ASCII")
    result
  end

  # @param string [String] A URL-encoded value to convert into a normal string
  # @return [String] A plain Ruby string, with URL-encoding reversed
  def self.decode(string)
    encoding = string.encoding
    replaced_string = string.b.gsub(/((?:%[0-9a-fA-F]{2})+)/) do |m|
      [m.delete("%")].pack("H*")
    end
    replaced_string.force_encoding(encoding)
  end
end
