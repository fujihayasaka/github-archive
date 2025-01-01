# typed: true
# frozen_string_literal: true

module GitHub
  class Unidecode
    # Contains Unicode codepoints, loading as needed from YAML files
    CODEPOINTS = JSON.parse(File.read(File.expand_path("../unidecode/codepoints.json", __FILE__)))
    CODEPOINTS.transform_keys!(&:to_i)
    CODEPOINTS.values.each do |points|
      points.map! { |c| -c.to_s }
    end
    CODEPOINTS.default = (["?"] * 256).freeze
    CODEPOINTS.freeze

    # Returns string with its UTF-8 characters transliterated to ASCII ones
    def self.decode(string)

      # We get in a very unfortunate state if we get passed ASCII-8BIT
      # encoding, so we'd much rather just bail than get ourselves
      # confused.
      if string.respond_to?(:encoding) && string.encoding.to_s != "UTF-8"
        return string
      end

      string.gsub(/[^\x00-\x00]/u) do |codepoint|
        unpacked = codepoint.unpack("U")[0]
        CODEPOINTS[code_group(unpacked)][grouped_point(unpacked)]
      end
    end

    # Returns the Unicode codepoint grouping for the given character
    def self.code_group(unpacked_character)
      unpacked_character >> 8
    end
    private_class_method :code_group

    # Returns the index of the given character in the YAML file for its codepoint group
    def self.grouped_point(unpacked_character)
      unpacked_character & 255
    end
    private_class_method :grouped_point
  end
end
