# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class DiscussionCommentOrderField < Platform::Enums::Base
      description "Properties by which discussion comment connections can be ordered."
      visibility :under_development

      value "CREATED_AT", "Order discussion comments by creation time.", value: "created_at"
      value "UPDATED_AT", "Order discussion comments by updated time.", value: "updated_at"
    end
  end
end
