# typed: true
# frozen_string_literal: true

class TrackingBlock
  attr_reader :id
  attr_reader :issue

  def initialize(id:, issue:)
    @id = id
    @issue = issue
  end

  def ==(other)
    id == other.id &&
      issue == other.issue
  end

  def url
    EscapeHelper.safe_join([issue.url, "#tasklist-block-#{id}"])
  end
end
