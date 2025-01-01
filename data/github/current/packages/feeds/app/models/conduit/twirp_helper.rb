# typed: false
# frozen_string_literal: true

require "monolith-twirp-conduit-feeds"

module Conduit
  module TwirpHelper
    def followed_action?
      self.action == TwirpHelper.followed_action
    end

    def sponsorable_action?
      self.action == TwirpHelper.sponsorable_action
    end

    def starred_action?
      self.action == TwirpHelper.starred_action
    end

    def created_action?
      self.action == TwirpHelper.created_action
    end

    def forked_action?
      self.action == TwirpHelper.forked_action
    end

    def sponsored_action?
      self.action == TwirpHelper.sponsored_action
    end

    def recommended_action?
      self.action == TwirpHelper.recommended_action
    end

    def added_to_list_action?
      self.action == TwirpHelper.added_to_list_action
    end

    def near_sponsors_goal_action?
      self.action == TwirpHelper.near_sponsors_goal_action
    end

    def trending_repo_action?
      self.action == TwirpHelper.trending_repo_action
    end

    def labeled_action?
      self.action == TwirpHelper.labeled_action
    end

    def reopened_action?
      self.action == TwirpHelper.reopened_action
    end

    def self.key_for_item(twirp_item)
      "#{twirp_item.action}_#{twirp_item.subject_type}"
    end

    def self.starred_repository_key
      "#{starred_action}_#{repository_subject_type}"
    end

    def self.forked_repository_key
      "#{forked_action}_#{repository_subject_type}"
    end

    def self.created_repository_key
      "#{created_action}_#{repository_subject_type}"
    end

    def self.published_release_key
      "#{published_action}_#{release_subject_type}"
    end

    def self.created_discussion_key
      "#{created_action}_#{discussion_subject_type}"
    end

    def self.sponsored_user_key
      "#{sponsored_action}_#{user_subject_type}"
    end

    def self.followed_user_key
      "#{followed_action}_#{user_subject_type}"
    end

    def self.sponsorable_user_key
      "#{sponsorable_action}_#{user_subject_type}"
    end

    def self.repository_recommendation_key
      "#{recommended_action}_#{repository_subject_type}"
    end

    def self.added_to_list_key
      "#{added_to_list_action}_#{user_list_item_subject_type}"
    end

    def self.near_sponsors_goal_key
      "#{near_sponsors_goal_action}_#{user_subject_type}"
    end

    def self.merged_pull_request_key
      "#{merged_action}_#{pull_request_subject_type}"
    end

    def self.follow_recommendation_key
      "#{recommended_action}_#{user_subject_type}"
    end

    def self.created_feed_post_key
      "#{created_action}_#{feed_post_subject_type}"
    end

    def self.trending_repository_key
      "#{trending_repo_action}_#{repository_subject_type}"
    end

    def self.private_to_public_repository_key
      "#{published_action}_#{repository_subject_type}"
    end

    def self.labeled_issue_key
      "#{labeled_action}_#{issue_subject_type}"
    end

    def self.labeled_pull_request_key
      "#{labeled_action}_#{pull_request_subject_type}"
    end

    def self.closed_pull_request_key
      "#{closed_action}_#{pull_request_subject_type}"
    end

    def self.created_issue_key
      "#{created_action}_#{issue_subject_type}"
    end

    def self.created_pull_request_key
      "#{created_action}_#{pull_request_subject_type}"
    end

    def self.created_pull_request_review_key
      "#{created_action}_#{pull_request_review_subject_type}"
    end

    def self.closed_issue_key
      "#{closed_action}_#{issue_subject_type}"
    end

    def self.reopened_issue_key
      "#{reopened_action}_#{issue_subject_type}"
    end

    def self.reopened_pull_request_key
      "#{reopened_action}_#{pull_request_subject_type}"
    end

    def self.member_add_to_repository_key
      "#{updated_action}_#{repository_subject_type}"
    end

    def self.created_pull_request_comment_key
      "#{created_action}_#{pull_request_comment_subject_type}"
    end

    def self.created_pr_review_comment_key
      "#{created_action}_#{pull_request_review_comment_subject_type}"
    end

    def self.created_issue_comment_key
      "#{created_action}_#{issue_comment_subject_type}"
    end

    def self.created_commit_comment_key
      "#{created_action}_#{commit_comment_subject_type}"
    end

    def self.followed_action
      action_class.lookup(
        action_class.const_get(:ACTION_FOLLOWED)
      )
    end

    def self.published_push_key
      "#{published_action}_#{push_subject_type}"
    end

    def self.published_action
      action_class.lookup(
        action_class.const_get(:ACTION_PUBLISHED)
      )
    end

    def self.sponsored_action
      action_class.lookup(
        action_class.const_get(:ACTION_SPONSORED)
      )
    end

    def self.starred_action
      action_class.lookup(
        action_class.const_get(:ACTION_STARRED)
      )
    end

    def self.forked_action
      action_class.lookup(
        action_class.const_get(:ACTION_FORKED)
      )
    end

    def self.sponsorable_action
      action_class.lookup(
        action_class.const_get(:ACTION_SPONSORABLE)
      )
    end

    def self.created_action
      action_class.lookup(
        action_class.const_get(:ACTION_CREATED)
      )
    end

    def self.added_to_list_action
      action_class.lookup(
        action_class.const_get(:ACTION_ADDED_TO_LIST)
      )
    end

    def self.recommended_action
      action_class.lookup(
        action_class.const_get(:ACTION_RECOMMENDED)
      )
    end

    def self.near_sponsors_goal_action
      action_class.lookup(
        action_class.const_get(:ACTION_NEAR_SPONSORS_GOAL)
      )
    end

    def self.merged_action
      action_class.lookup(
        action_class.const_get(:ACTION_MERGED)
      )
    end

    def self.trending_repo_action
      action_class.lookup(
        action_class.const_get(:ACTION_TRENDING_REPO)
      )
    end

    def self.labeled_action
      action_class.lookup(
        action_class.const_get(:ACTION_LABELED)
      )
    end

    def self.closed_action
      action_class.lookup(
        action_class.const_get(:ACTION_CLOSED)
      )
    end

    def self.reopened_action
      action_class.lookup(
        action_class.const_get(:ACTION_REOPENED)
      )
    end

    def self.updated_action
      action_class.lookup(
        action_class.const_get(:ACTION_UPDATED)
      )
    end

    def self.release_subject_type
      subject_type_class.lookup(
        subject_type_class.const_get(:SUBJECT_TYPE_RELEASE)
      )
    end

    def self.discussion_subject_type
      subject_type_class.lookup(
        subject_type_class.const_get(:SUBJECT_TYPE_DISCUSSION)
      )
    end

    def self.repository_subject_type
      subject_type_class.lookup(
        subject_type_class.const_get(:SUBJECT_TYPE_REPOSITORY)
      )
    end

    def self.user_subject_type
      subject_type_class.lookup(
        subject_type_class.const_get(:SUBJECT_TYPE_USER)
      )
    end

    def self.user_list_item_subject_type
      subject_type_class.lookup(
        subject_type_class.const_get(:SUBJECT_TYPE_USER_LIST_ITEM)
      )
    end

    def self.pull_request_subject_type
      subject_type_class.lookup(
        subject_type_class.const_get(:SUBJECT_TYPE_PULL_REQUEST)
      )
    end

    def self.pull_request_review_subject_type
      subject_type_class.lookup(
        subject_type_class.const_get(:SUBJECT_TYPE_PULL_REQUEST_REVIEW)
      )
    end

    def self.pull_request_review_comment_subject_type
      subject_type_class.lookup(
        subject_type_class.const_get(:SUBJECT_TYPE_PULL_REQUEST_REVIEW_COMMENT)
      )
    end

    def self.pull_request_comment_subject_type
      subject_type_class.lookup(
        subject_type_class.const_get(:SUBJECT_TYPE_PULL_REQUEST_COMMENT)
      )
    end

    def self.issue_comment_subject_type
      subject_type_class.lookup(
        subject_type_class.const_get(:SUBJECT_TYPE_ISSUE_COMMENT)
      )
    end

    def self.commit_comment_subject_type
      subject_type_class.lookup(
        subject_type_class.const_get(:SUBJECT_TYPE_COMMIT_COMMENT)
      )
    end

    def self.feed_post_subject_type
      subject_type_class.lookup(
        subject_type_class.const_get(:SUBJECT_TYPE_FEED_POST)
      )
    end

    def self.issue_subject_type
      subject_type_class.lookup(
        subject_type_class.const_get(:SUBJECT_TYPE_ISSUE)
      )
    end

    def self.push_subject_type
      subject_type_class.lookup(
        subject_type_class.const_get(:SUBJECT_TYPE_PUSH)
      )
    end

    def self.action_class
      MonolithTwirp::Conduit::Feeds::V1::FeedItem::Action
    end

    def self.subject_type_class
      MonolithTwirp::Conduit::Feeds::V1::FeedItem::SubjectType
    end
  end
end
