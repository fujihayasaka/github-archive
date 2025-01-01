# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CommitContributionOrderField < Platform::Enums::Base
      description "Properties by which commit contribution connections can be ordered."

      value "OCCURRED_AT", "Order commit contributions by when they were made.",
        value: "occurred_at"
      value "COMMIT_COUNT", "Order commit contributions by how many commits they represent.",
        value: "commit_count"
    end
  end
end
