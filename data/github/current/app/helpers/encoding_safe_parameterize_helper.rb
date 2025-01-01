# typed: true
# frozen_string_literal: true

# Aids in use of `parameterize` with non-utf-8 strings
module EncodingSafeParameterizeHelper
  # Parameterizes a string using String#parameterize but first checks for
  # some encoding issues and attempts to resolve them.
  #
  # string        - The string to parameterize
  # separator     - The string to use as a separator
  # preserve_case - Pass `true` to preserve case
  #
  # In the case of a binary / ASCII-8BIT string, force_encoding is used to tag
  # the string as UTF-8. Byte sequences which are invalid in UTF-8 are scrubbed.
  def encoding_safe_parameterize(string, separator: "-", preserve_case: false)
    # If this is ASCII-8BIT force encoding to UTF-8 & scrub
    if string.encoding == Encoding::ASCII_8BIT
      string = string.dup.force_encoding(::Encoding::UTF_8).scrub!("")
    end

    string.parameterize(separator: separator, preserve_case: preserve_case)
  end
  module_function :encoding_safe_parameterize
end
