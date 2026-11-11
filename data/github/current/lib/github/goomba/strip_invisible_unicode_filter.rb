# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class StripInvisibleUnicodeFilter < InputFilter
    # Invisible Unicode characters to strip:
    # \u200B - Zero Width Space
    # \u200C - Zero Width Non-Joiner
    # \u200D - Zero Width Joiner
    # \u200E - Left-to-Right Mark
    # \u200F - Right-to-Left Mark
    # \u202A - Left-to-Right Embedding
    # \u202B - Right-to-Left Embedding
    # \u202C - Pop Directional Formatting
    # \u202D - Left-to-Right Override
    # \u202E - Right-to-Left Override
    # \u2060 - Word Joiner
    # \u2061 - Function Application
    # \u2062 - Invisible Times
    # \u2063 - Invisible Separator
    # \u2064 - Invisible Plus
    # \uFEFF - Zero Width No-Break Space
    # \u180E - Mongolian Vowel Separator
    # \u061C - Arabic Letter Mark
    INVISIBLE_UNICODE_PATTERN = /[\u200B\u200C\u200D\u200E\u200F\u202A\u202B\u202C\u202D\u202E\u2060\u2061\u2062\u2063\u2064\uFEFF\u180E\u061C]/

    def call(text)
      text.gsub(INVISIBLE_UNICODE_PATTERN, "")
    end
  end
end
