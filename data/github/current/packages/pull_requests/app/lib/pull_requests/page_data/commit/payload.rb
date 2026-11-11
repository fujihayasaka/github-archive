# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Commit
  class Payload
    class Author < T::Struct
      const :login, T.nilable(String)
      const :displayName, String
      const :avatarUrl, String
      const :path, T.nilable(String)
      const :isGitHub, T::Boolean
    end

    class Committer < T::Struct
      const :login, T.nilable(String)
      const :displayName, String
      const :avatarUrl, String
      const :path, T.nilable(String)
      const :isGitHub, T::Boolean
    end

    class Pusher < T::Struct
      const :login, String
      const :displayName, String
      const :avatarUrl, String
      const :path, String
      const :isGitHub, T::Boolean
    end

    class Payload < T::Struct
      const :oid, String
      const :url, String
      const :authoredDate, Time
      const :committedDate, Time
      const :shortMessageMarkdown, String
      const :bodyMessageHtml, T.nilable(String)
      const :authors, T::Array[Author]
      const :committerAttribution, T::Boolean
      const :committer, T.nilable(Committer)
      const :pusher, T.nilable(Pusher)
      const :pushedDate, T.nilable(String)
      const :parents, T::Array[String]
      const :globalRelayId, String
      const :sha1, String
      const :sha2, String
    end

    sig do
      params(
        commit_data: PullRequests::PageData::Commit::Loader::Data
      ).returns(Payload)
    end
    def self.call(commit_data)
      new(commit_data:).call
    end

    sig do
      params(
        commit_data: PullRequests::PageData::Commit::Loader::Data
      ).void
    end
    def initialize(commit_data:)
      @commit_data = commit_data
    end

    sig { returns(Payload) }
    def call
      Payload.new(
        oid: @commit_data.oid,
        url: @commit_data.url,
        authoredDate: @commit_data.authored_date,
        committedDate: @commit_data.committed_date,
        shortMessageMarkdown: @commit_data.short_message_markdown,
        bodyMessageHtml: @commit_data.body_message_html,
        authors: @commit_data.authors.map { |author| serialize_author(author) },
        committerAttribution: @commit_data.committer_attribution,
        committer: @commit_data.committer ? serialize_committer(T.must(@commit_data.committer)) : nil,
        pusher: @commit_data.pusher ? serialize_pusher(T.must(@commit_data.pusher)) : nil,
        pushedDate: @commit_data.pushed_date,
        parents: @commit_data.parents,
        globalRelayId: @commit_data.global_relay_id,
        sha1: @commit_data.sha1,
        sha2: @commit_data.sha2,
      )
    end

    private

    sig { params(author: PullRequests::PageData::Commit::Loader::Author).returns(Author) }
    def serialize_author(author)
      Author.new(
        login: author.login, # rubocop:disable GitHub/DoNotAllowLogin
        displayName: author.display_name,
        avatarUrl: author.avatar_url,
        path: author.path,
        isGitHub: author.is_github,
      )
    end

    sig { params(committer: PullRequests::PageData::Commit::Loader::Committer).returns(Committer) }
    def serialize_committer(committer)
      Committer.new(
        login: committer.login, # rubocop:disable GitHub/DoNotAllowLogin
        displayName: committer.display_name,
        avatarUrl: committer.avatar_url,
        path: committer.path,
        isGitHub: committer.is_github,
      )
    end

    sig { params(pusher: PullRequests::PageData::Commit::Loader::Pusher).returns(Pusher) }
    def serialize_pusher(pusher)
      Pusher.new(
        login: pusher.login, # rubocop:disable GitHub/DoNotAllowLogin
        displayName: pusher.display_name,
        avatarUrl: pusher.avatar_url,
        path: pusher.path,
        isGitHub: pusher.is_github,
      )
    end
  end
end
