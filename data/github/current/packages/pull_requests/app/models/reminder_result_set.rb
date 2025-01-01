# typed: true
# frozen_string_literal: true

class ReminderResultSet
  attr_reader :prs_for_review, :prs_for_author

  def initialize(prs_for_review, prs_for_author)
    @prs_for_review = prs_for_review
    @prs_for_author = prs_for_author
  end

  def empty?
    prs_for_review.empty? && prs_for_author.empty?
  end
end
