# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class IssueCommentOrderField < Platform::Enums::Base
      description "Properties by which issue comment connections can be ordered."

      value "UPDATED_AT", "Order issue comments by update time", value: "updated_at"
    end
  end
end
