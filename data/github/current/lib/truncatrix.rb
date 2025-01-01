# typed: true
# frozen_string_literal: true

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
    text.truncate_bytes(limit, omission: "") if !!text
  end
end
