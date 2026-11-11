# typed: true
# frozen_string_literal: true

module DiscussionsStafftoolsRoutesHelper
  include GitHub::RouteHelpers

  sig { params(repo: Repository).returns(String) }
  def gh_stafftools_repository_discussions_path(repo)
    expand_nwo_from :stafftools_repository_discussions_path, repo
  end

  sig { params(discussion: Discussion).returns(String) }
  def gh_stafftools_repository_discussion_path(discussion)
    expand_nwo_from :stafftools_repository_discussion_path, discussion
  end

  sig { params(discussion: Discussion).returns(String) }
  def gh_database_stafftools_repository_discussion_path(discussion)
    expand_nwo_from :database_stafftools_repository_discussion_path, discussion
  end

  sig { params(discussion: Discussion).returns(String) }
  def gh_database_stafftools_repository_discussion_lock_path(discussion)
    expand_nwo_from :lock_stafftools_repository_discussion_path, discussion
  end

  sig { params(discussion: Discussion).returns(String) }
  def gh_database_stafftools_repository_discussion_unlock_path(discussion)
    expand_nwo_from :unlock_stafftools_repository_discussion_path, discussion
  end

  sig { params(discussion: Discussion).returns(String) }
  def gh_stafftools_repository_discussion_subscriptions_path(discussion)
    expand_nwo_from :stafftools_repository_discussion_subscriptions_path, discussion
  end

  sig { params(discussion: Discussion).returns(String) }
  def gh_stafftools_repository_discussion_comments_path(discussion)
    expand_nwo_from :stafftools_repository_discussion_comments_path, discussion
  end

  sig { params(comment: DiscussionComment).returns(String) }
  def gh_stafftools_repository_discussion_comment_path(comment)
    expand_from_discussion_comment :stafftools_repository_discussion_comment_path, comment
  end

  sig { params(comment: DiscussionComment).returns(String) }
  def gh_database_stafftools_repository_discussion_comment_path(comment)
    expand_from_discussion_comment :database_stafftools_repository_discussion_comment_path, comment
  end

  sig { params(comment: DiscussionComment).returns(String) }
  def gh_nested_comments_stafftools_repository_discussion_comment_path(comment)
    expand_from_discussion_comment :nested_comments_stafftools_repository_discussion_comment_path, comment
  end

  private

  sig { params(helper: Symbol, comment: DiscussionComment).returns(String) }
  def expand_from_discussion_comment(helper, comment)
    discussion = comment.discussion
    repo = discussion&.repository
    case helper
    when :stafftools_repository_discussion_comment_path
      UrlHelpers.stafftools_repository_discussion_comment_path(repo&.owner, repo, discussion, comment)
    when :database_stafftools_repository_discussion_comment_path
      UrlHelpers.database_stafftools_repository_discussion_comment_path(repo&.owner, repo, discussion, comment)
    when :nested_comments_stafftools_repository_discussion_comment_path
      UrlHelpers.nested_comments_stafftools_repository_discussion_comment_path(repo&.owner, repo, discussion, comment)
    else
      raise "Unknown discussion comment route helper: #{helper}"
    end
  end
end
