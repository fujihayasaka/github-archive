# typed: strict
# frozen_string_literal: true

module CodeScanning
  class AlertMessagePlaceholderLinks
    PLACEHOLDER_LINK_REGEX = T.let(/\[([^\[]+)\]\((\d+)\)/, Regexp)

    sig { params(message_text: T.nilable(String)).returns(T.nilable(String)) }
    def self.strip_placeholder_links(message_text)
      return unless message_text

      message_text.gsub(PLACEHOLDER_LINK_REGEX, '\1')
    end

    sig do
      params(
        message_text: T.nilable(String),
        related_locations: T.any(T::Enumerable[Turboscan::Proto::RelatedLocation], T::Enumerable[Turboquality::Proto::RelatedLocation]),
      ).returns(T.nilable(String))
    end
    def self.replace_placeholder_links(message_text, related_locations:)
      return if message_text.nil? || message_text.empty?

      message_text.gsub(PLACEHOLDER_LINK_REGEX) do
        match = T.must(Regexp.last_match)
        link_text = T.must(match[1])
        link_index = T.must(match[2]).to_i
        related_location = related_location_from_link_index(link_index:, related_locations:)
        related_location_target = related_location && related_location_reference(related_location.location)
        link_target = related_location_target || link_index

        "[#{link_text}](#{link_target})"
      end
    end

    sig do
      params(
        link_index: Integer,
        related_locations: T.any(T::Enumerable[Turboscan::Proto::RelatedLocation], T::Enumerable[Turboquality::Proto::RelatedLocation]),
      ).returns(T.nilable(T.any(Turboscan::Proto::RelatedLocation, Turboquality::Proto::RelatedLocation)))
    end
    def self.related_location_from_link_index(link_index:, related_locations:)
      related_locations.find do |loc|
        next loc.replacement_index == link_index if loc.is_a?(Turboscan::Proto::RelatedLocation)
        next loc.id == link_index if loc.is_a?(Turboquality::Proto::RelatedLocation)

        false
      end
    end

    sig { params(location: T.nilable(T.any(Turboscan::Proto::Location, Turboquality::Proto::Location))).returns(T.nilable(String)) }
    def self.related_location_reference(location)
      return nil if location.nil?

      file_path = location.file_path.to_s.presence
      return nil if file_path.nil?

      start_line = location.start_line.nonzero?
      end_line = location.end_line.nonzero?
      start_column = location.start_column.nonzero?
      end_column = location.end_column.nonzero?

      return file_path if start_line.nil? && end_line.nil?
      start_line ||= end_line
      end_line ||= start_line

      if start_column.nil? && end_column.nil?
        return "#{file_path}#L#{start_line}" if start_line == end_line

        return "#{file_path}#L#{start_line}-L#{end_line}"
      end

      start_column ||= end_column
      end_column ||= start_column

      if start_line == end_line && start_column == end_column
        return "#{file_path}#L#{start_line}C#{start_column}"
      end

      "#{file_path}#L#{start_line}C#{start_column}-L#{end_line}C#{end_column}"
    end

    private_class_method :related_location_from_link_index
    private_class_method :related_location_reference
  end
end
