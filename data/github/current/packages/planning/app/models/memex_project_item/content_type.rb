# typed: true
# frozen_string_literal: true

# Represents valid values for the `memex_project_items.content_type` database column.
class MemexProjectItem::ContentType < T::Enum
  enums do
    DraftIssue = new("DraftIssue")
    Issue = new("Issue")
    PullRequest = new("PullRequest")
  end
end
