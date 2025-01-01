# typed: strict
# frozen_string_literal: true

module CustomPropertiesCore
  module Public
    # Public: Max number of property definitions per org
    DEFINITION_LIMIT = 100

    # Public: Max length of property names and values
    MAX_LENGTH = 75

    # Public: Max length of the description of a property
    DESCRIPTION_MAX_LENGTH = 255

    NAME_VALID_CHARS_REGEX_TEXT = "[a-zA-Z0-9_\\#\\$\\-]+"
    # Public: Regex to validate allowed characters in property names
    NAME_VALID_CHARS_REGEX = /\A#{NAME_VALID_CHARS_REGEX_TEXT}\z/

    # Public: Regex to find forbidden characters in property values. Allows all printable ASCII characters except
    # double quotes.
    #
    # This regex works because `"` is between `!` and `#` in the ASCII table.
    VALUE_INVALID_CHARS_REGEX = /[^ -!#-~]/
  end
end
