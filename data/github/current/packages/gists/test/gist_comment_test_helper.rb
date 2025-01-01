# typed: true
# frozen_string_literal: true

module GistCommentTestHelper
  def gist_test_content_array
    [
      { name: "1", value: "random content" },
    ]
  end

  def spammy_comment
    "Buy viagra here: http://i.am.spam.com/rawr"
  end
end
