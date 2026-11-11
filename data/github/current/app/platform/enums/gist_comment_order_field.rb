# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class GistCommentOrderField < Platform::Enums::Base
      description "Properties by which gist comment connections can be ordered."

      value "UPDATED_AT", "Order gist comments by updated at time.", value: "updated_at"
    end
  end
end
