# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CommitCommentOrderField < Platform::Enums::Base
      description "Properties by which commit comment connections can be ordered."

      value "UPDATED_AT", "Order commit comments by update time", value: "updated_at"
    end
  end
end
