# typed: true
# frozen_string_literal: true

# Mixin for CommitComments, Issues, IssueComments, PullRequests,
# PullRequestReviews, PullRequestReviewComments, and GistComments
# to expose an `#author_association` helper method
module AuthorAssociable
  # Returns the comment's author association (e.g., first time contributor)
  #
  # viewer - the current user, used to scope organization membership discoverability
  #
  # Returns an AuthorAssociation
  def author_association(viewer = nil)
    CommentAuthorAssociation.new(comment: self, viewer: viewer)
  end

  def author_association_symbol(viewer = nil)
    return @author_association_symbol if defined?(@author_association_symbol)
    @author_association_symbol = CommentAuthorAssociation.new(comment: self, viewer: viewer).async_to_sym.sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end
end
