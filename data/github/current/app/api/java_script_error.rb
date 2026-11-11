# typed: true
# frozen_string_literal: true

class Api::JavaScriptError < Api::Error
  def initialize(error)
    super error[:message] || error["message"]
    set_backtrace(error[:stack] || error["stack"])
  end
end
