# typed: true
# frozen_string_literal: true

module Notifyd

  # ReplyToToken generates a token that a user can use to reply to a thread via email by parsing notification_id
  # It uses `GitHub::Email::Token.target_token` which is also used in Newsies
  class ReplyToToken

    class Target
      attr_reader :notification_id

      def initialize(notification_id)
        @notification_id = notification_id
      end

      def get
        case [thread, sub_thread]
        in [*, ["discussioncomment", id]]
          DiscussionComment.find_by(id: id)
        in [*, ["issuecomment", id]]
          IssueComment.find_by(id: id)
        in [*, ["gistcomment", id]]
          GistComment.find_by(id: id)
        in [*, ["pullrequestreview", id]]
          PullRequestReview.find_by(id: id)
        in [*, ["event", id]]
          IssueEventNotification.find(id)
        in [[*, owner_login, repo_name, "issues", number], nil]
          repository = Repository.find_by(name: repo_name, owner_login: owner_login)
          Issue.find_by(repository: repository, number: number) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        in [[*, owner_login, repo_name, "discussions", number], nil]
          repository = Repository.find_by(name: repo_name, owner_login: owner_login)
          Discussion.find_by(repository: repository, number: number)
        else
          nil
        end
      end

      private

      def parse_uri
        URI.parse(notification_id)
      rescue URI::InvalidURIError
        URI("")
      end

      def uri
        @uri ||= parse_uri
      end

      def thread
        uri.path.split("/")
      end

      def sub_thread
        uri.fragment&.split("-")
      end
    end

    attr_reader :notification_id, :user

    def initialize(user, notification_id)
      @user = user
      @notification_id = notification_id
    end

    def generate
      GitHub::Email::Token.target_token(target, user) if target.present? && user.present?
    end

    private

    def target
      @target ||= Target.new(notification_id).get
    end
  end
end
