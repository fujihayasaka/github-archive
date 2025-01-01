# typed: true
# frozen_string_literal: true

module Codespaces
  class GenerateName < Command
    # It can contain "-"s but cannot start or end with them.
    NAME_DISALLOWED_BOUNDARY_CHARS_REGEX = /\A-|-\z/

    attr_reader :display_name, :owner, :suffix, :max_name_length

    def initialize(display_name:, owner:, suffix: nil, max_name_length: Codespace::MAX_NAME_LENGTH)
      @display_name = display_name
      @owner = owner
      @suffix = suffix || Codespaces.hashid.encode(owner.id.to_s + SecureRandom.random_number(999).to_s, SecureRandom.random_number(9999))
      @max_name_length = max_name_length
    end

    def perform
      segments = {
        display_name: display_name,
        suffix: suffix.presence,
      }.compact

      segments.transform_values! do |value|
        value.gsub(/[^#{Codespace::NAME_ALLOWED_CHARS_REGEX}]/i, "-")
          .downcase
          .gsub(NAME_DISALLOWED_BOUNDARY_CHARS_REGEX, "")
      end

      format_with_max_length(segments: segments)
    end

    private

    def format_with_max_length(segments:)
      name = segments.values.join("-")
      return name if name.length <= max_name_length

      suffix, display_name = segments.values_at(:suffix, :display_name)

      truncated_length = max_name_length
      truncated_length -= suffix.length + 1 if suffix.present? # add 1 to what we subtract for the hyphen we join with

      truncated_name = display_name.truncate(truncated_length, omission: "", separator: /[\s\-\_]/)
      [truncated_name, suffix].compact.join("-")
    end
  end
end
