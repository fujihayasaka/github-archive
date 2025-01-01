# typed: strict
# frozen_string_literal: true

module Releases
  # [title, body, warning]
  IReleaseNotes = T.type_alias do
    [String, String, String]
  end
end
