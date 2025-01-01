# typed: true
# frozen_string_literal: true

class PullRequestReview::Collection
  include Enumerable
  def initialize(reviews)
    @reviews = reviews
  end

  # Iterate through each PullRequestReviewSet in the collection.
  #
  # Returns an Enumerator.
  def each(&block)
    @reviews.each(&block)
  end

  # Return a new PullRequestReviewSet that filters out the dismissed reviews
  def excluding_dismissed
    self.class.new(reject(&:dismissed?))
  end

  def changes_requested?
    any?(&:changes_requested?)
  end

  def approved?
    !changes_requested? && any?(&:approved?)
  end
end
