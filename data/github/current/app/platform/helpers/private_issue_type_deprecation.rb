# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    class PrivateIssueTypeDeprecation
      NOTICE = {
        start_date: Date.new(2024, 10, 1),
        reason: "Private issue types are being deprecated and can no longer be created.",
        superseded_by: nil,
        owner: "github/issues",
      }
    end
  end
end
