# typed: strict
# frozen_string_literal: true

module CustomPropertiesCore
  module Public
    # Public: Max number of property definitions per org
    DEFINITION_LIMIT = 100

    # Public: Max length of property names
    MAX_PROPERTY_NAME_LENGTH = 75

    # Public: Max length of the description of a property
    DESCRIPTION_MAX_LENGTH = 255

    NAME_VALID_CHARS_REGEX_TEXT = "[a-zA-Z0-9_\\#\\$\\-]+"
    # Public: Regex to validate allowed characters in property names
    NAME_VALID_CHARS_REGEX = /\A#{NAME_VALID_CHARS_REGEX_TEXT}\z/

    # Public: Max length of namespace display names
    MAX_NAMESPACE_DISPLAY_NAME_LENGTH = 15

    NAMESPACE_DISPLAY_NAME_VALID_CHARS_REGEX_TEXT = "[a-zA-Z0-9]+"
    # Public: Regex to validate allowed characters in namespace display names (alphanumeric only)
    NAMESPACE_DISPLAY_NAME_VALID_CHARS_REGEX = /\A#{NAMESPACE_DISPLAY_NAME_VALID_CHARS_REGEX_TEXT}\z/

    # Public: Reserved namespace display names that cannot be used
    RESERVED_NAMESPACE_DISPLAY_NAMES = T.let(%w[p props properties].freeze, T::Array[String])

    # Public: Regex to find forbidden characters in property values. Allows all printable ASCII characters except
    # double quotes.
    #
    # This regex works because `"` is between `!` and `#` in the ASCII table.
    VALUE_INVALID_CHARS_REGEX = /[^ -!#-~]/
  end
end
