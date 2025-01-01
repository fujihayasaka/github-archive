# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PullRequestOrderField < Platform::Enums::Base
      description "Properties by which pull_requests connections can be ordered."

      value "CREATED_AT", "Order pull_requests by creation time", value: "created_at"
      value "UPDATED_AT", "Order pull_requests by update time", value: "updated_at"
    end
  end
end
