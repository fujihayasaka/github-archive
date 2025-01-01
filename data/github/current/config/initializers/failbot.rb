# typed: true
# frozen_string_literal: true

require "failbot"

module Failbot
  def report_user_error(e, extra = {})
    report(e, extra.merge(app: "github-user"))
  end

  def report_trace(e, extra = {})
    report(e, extra.merge(app: "github-tracing"))
  end
end
