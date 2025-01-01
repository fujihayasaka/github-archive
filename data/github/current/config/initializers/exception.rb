# typed: true
# frozen_string_literal: true

class Exception
  # In some cases, like GitHub.auth.log we want to be able to log an exception
  # to an existing hash. This monkey patch prevents us from having to check
  # whether we have an exception object or a hash and let's the code just
  # handle it.
  def to_hash(extra = nil)
    h = { "message" => message }
    h = h.merge("backtrace" => backtrace) if %w{development staging test}.include?(GitHub::AppEnvironment.env)
    h = h.merge(extra) if extra
    h
  end
end
