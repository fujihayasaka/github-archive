# typed: true
# frozen_string_literal: true

# This is a short-lived thing to help investigate
# a truncation issue in the API.
require "active_support/core_ext/string/multibyte"
require "active_support/core_ext/string/filters"
class Truncatrix
  attr_reader :text, :limit
  def initialize(text:, limit:)
    @text  = text
    @limit = limit
  end

  def bytes_exceeded
    return 0 unless limit_exceeded?

    text.bytesize - limit
  end

  def bytes_truncated
    return 0 unless limit_exceeded?

    text.bytesize - truncated_text.bytesize
  end

  def limit_exceeded?
    return false if text.nil?

    text.bytesize > limit
  end

  def truncated_text
    text.mb_chars.limit(limit).to_s if !!text
  end
end
