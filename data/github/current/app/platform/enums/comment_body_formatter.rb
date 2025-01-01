# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CommentBodyFormatter < Platform::Enums::Base
      description "The formatter used to process the comment body in our HTML pipeline."
      visibility :internal

      value "MARKDOWN", "The comment body should be processed as GitHub-flavored Markdown.", value: "markdown"
      value "EMAIL", "The comment body was created from an email, and should be processed as such.", value: "email"
    end
  end
end
