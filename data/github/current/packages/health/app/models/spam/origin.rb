# typed: true
# frozen_string_literal: true

module Spam
  class Origin
    @@console_origin = :console

    def self.console_origin
      @@console_origin
    end

    def self.console_origin=(new_console_origin)
      @@console_origin = new_console_origin
    end

    def self.call(origin)
      origin ||= GitHub.component == :console && console_origin
      origin ||= GitHub.component == :resque && :resque
      origin ||= GitHub.component == :resque_deliver_notifications && :resque_deliver_notifications
      origin ||= GitHub.component == :resque_wiki_page_spam_check && :resque_wiki_page_spam_check
      origin ||= GitHub.component == :resque_check_for_spam_issue_comment && :resque_check_for_spam_issue_comment
      origin ||= GitHub.component == :resque_check_for_spam_issue && :resque_check_for_spam_issue
      origin ||= GitHub.component == :resque_check_for_spam_repository && :resque_check_for_spam_repository
      origin ||= GitHub.component == :resque_check_for_spam_gist && :resque_check_for_spam_gist
      origin ||= GitHub.component == :resque_check_for_spam_profile && :resque_check_for_spam_profile
      origin ||= GitHub.component == :resque_check_for_spam_commit_comment && :resque_check_for_spam_commit_comment
      origin ||= GitHub.component == :resque_check_for_spam_pull_request_review_comment && :resque_check_for_spam_pull_request_review_comment
      origin ||= GitHub.component == :resque_check_for_spam_organization && :resque_check_for_spam_organization
      origin ||= GitHub.component == :resque_check_for_spam_mannequin && :resque_check_for_spam_mannequin
      origin ||= GitHub.component == :resque_check_for_spam_gist_comment && :resque_check_for_spam_gist_comment
      origin ||= GitHub.component == :resque_check_for_spam_bot && :resque_check_for_spam_bot
      origin ||= GitHub.component == :resque_check_for_spam_user && :resque_check_for_spam_user
      origin ||= :dotcom
      origin
    end
  end
end
