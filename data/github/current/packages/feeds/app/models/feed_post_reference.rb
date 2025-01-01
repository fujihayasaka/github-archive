# typed: true
# frozen_string_literal: true

class FeedPostReference < ApplicationRecord::Ballast
  belongs_to :feed_post, required: true
  belongs_to :reference, polymorphic: true, required: true

  enum :reference_type, {
    "User": 0,
    "Issue": 1,
    "PullRequest": 2,
    "Repository": 3,
    "Discussion": 4,
  }

  # Public: Parses FeedPost#body and returns
  # unpersisted FeedPostReference objects
  def self.from_post(post)
    user_mentions = parse_user_mentions(post)
    issue_mentions = parse_issue_mentions(post)
    repo_mentions = parse_repo_mentions(post)
    discussion_mentions = parse_discussion_mentions(post)

    user_mentions + issue_mentions + repo_mentions + discussion_mentions
  end

  def self.parse_user_mentions(post)
    logins = []
    GitHub::HTML::MentionFilter.mentioned_logins_in(post.body) do |_, login, _|
      logins << login
    end

    User.where(login: logins).map do |user|
      FeedPostReference.new(feed_post: post, reference: user)
    end
  end

  def self.parse_issue_mentions(post)
    viewer = post.owner
    filter = DraftIssueReferenceFilter.new(text: post.body, viewer: viewer, multi_refs: true)
    filter.references.map do |issue|
      FeedPostReference.new(feed_post: post, reference: issue)
    end
  end

  def self.parse_repo_mentions(post)
    viewer = post.owner
    filter = RepositoryReferenceScanner.new(text: post.body, viewer: viewer)
    filter.references.map do |issue|
      FeedPostReference.new(feed_post: post, reference: issue)
    end
  end

  def self.parse_discussion_mentions(post)
    viewer = post.owner
    filter = DiscussionReferenceScanner.new(text: post.body, viewer: viewer)
    filter.references.map do |discussion|
      FeedPostReference.new(feed_post: post, reference: discussion)
    end
  end

  def action
    case reference_type
    when "User", "Issue", "PullRequest", "Repository", "Discussion"
      "mention"
    end
  end
end
