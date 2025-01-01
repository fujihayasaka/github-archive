# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class UserAssociatedRecordType < Platform::Enums::Base
      description "The possible user-associated record types."
      visibility :internal

      value "COMMIT_COMMENT", "Commit comment.", value: :commit_comments
      value "DISCUSSION", "Discussion.", value: :discussions
      value "DISCUSSION_COMMENT", "Discussion comment.", value: :discussion_comments
      value "FAN", "Fan (aka follower).", value: :followeds
      value "GIST", "Gist.", value: :gists
      value "GIST_COMMENT", "Gist comment.", value: :gist_comments
      value "HERO", "Hero (aka following).", value: :followings
      value "ISSUE", "Issue.", value: :issues
      value "ISSUE_COMMENT", "Issue comment.", value: :issue_comments
      value "PROJECT", "Project.", value: :projects
      value "PROJECT_CARD", "Project card.", value: :project_cards
      value "PROJECT_NEXT", "ProjectNext.", value: :created_memex_projects
      value "PROJECT_NEXT_ITEM", "ProjectNext item.", value: :memex_project_items
      value "PROJECT_NEXT_ITEM_FIELD_VALUE", "ProjectNext item field value.", value: :memex_project_column_values
      value "PULL", "Pull Request.", value: :pull_requests
      value "REPO", "Repository.", value: :repositories
      value "STAR", "Star.", value: :stars
    end
  end
end
