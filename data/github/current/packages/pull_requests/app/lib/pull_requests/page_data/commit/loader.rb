# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Commit
  class Loader
    include UrlHelper

    class Author < T::Struct
      const :login, T.nilable(String)
      const :display_name, String
      const :avatar_url, String
      const :path, T.nilable(String)
      const :is_github, T::Boolean
    end

    class Committer < T::Struct
      const :login, T.nilable(String)
      const :display_name, String
      const :avatar_url, String
      const :path, T.nilable(String)
      const :is_github, T::Boolean
    end

    class Pusher < T::Struct
      const :login, String
      const :display_name, String
      const :avatar_url, String
      const :path, String
      const :is_github, T::Boolean
    end

    class PusherResult < T::Struct
      const :pusher, T.nilable(Pusher)
      const :pushed_date, T.nilable(String)
    end

    class Data < T::Struct
      const :oid, String
      const :url, String
      const :authored_date, Time
      const :committed_date, Time
      const :short_message_markdown, String
      const :body_message_html, T.nilable(String)
      const :authors, T::Array[Author]
      const :committer_attribution, T::Boolean
      const :committer, T.nilable(Committer)
      const :pusher, T.nilable(Pusher)
      const :pushed_date, T.nilable(String)
      const :parents, T::Array[String]
      const :global_relay_id, String
      const :sha1, String
      const :sha2, String
    end

    sig do
      params(
        commit: Commit,
        current_user: T.nilable(User)
      ).returns(Data)
    end
    def self.load(commit:, current_user:)
      new(commit:, current_user:).load
    end

    sig do
      params(
        commits: T::Array[Commit],
        current_user: T.nilable(User)
      ).void
    end
    def self.prefill_associations(commits:, current_user:)
      return unless commits.present?

      core_promises = commits.flat_map do |commit|
        [
          commit.async_full_subject_html(viewer: current_user),
          commit.async_full_body_html(viewer: current_user),
        ]
      end

      # Prefill author associations
      author_promises = commits.flat_map do |commit|
        [
          commit.author_actors.map { |git_actor| [git_actor.async_visible_actor(current_user)] },
          commit.committer_actor.async_visible_actor(current_user),
          commit.async_authored_by_committer?,
          commit.async_unique_visible_author_actors(current_user).then { |authors| authors.map { |author| author.async_visible_user(current_user) } },
        ].flatten
      end

      core_promises.concat(author_promises)

      Promise.all(core_promises).sync
    end

    sig do
      params(
        commit: Commit,
        current_user: T.nilable(User)
      ).void
    end
    def initialize(commit:, current_user:)
      @commit = commit
      @current_user = current_user
    end

    sig { returns(Data) }
    def load
      # Build authors, committer, and pusher
      authors_data = build_commit_authors
      committer_attribution = !@commit.async_authored_by_committer?.sync && !@commit.committed_via_web?
      committer_data = build_committer

      pusher_data = nil
      pushed_date = nil
      if @commit.repository&.feature_flag_enabled_or_raise?(:show_pusher_on_commit_detail) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        pusher_result = build_pusher
        pusher_data = pusher_result.pusher
        pushed_date = pusher_result.pushed_date
      end

      Data.new(
        oid: @commit.oid,
        url: commit_path(@commit, @commit.repository),
        authored_date: @commit.authored_date,
        committed_date: @commit.committed_date,
        short_message_markdown: @commit.full_subject_html(viewer: @current_user).to_s,
        body_message_html: @commit.full_body_html(viewer: @current_user),
        authors: authors_data,
        committer_attribution: committer_attribution,
        committer: committer_data,
        pusher: pusher_data,
        pushed_date: pushed_date,
        parents: @commit.parent_oids,
        global_relay_id: @commit.global_relay_id,
        sha1: @commit.first_parent_oid || "",
        sha2: @commit.oid,
      )
    end

    private

    sig { returns(T::Array[Author]) }
    def build_commit_authors
      authors = @commit.async_unique_visible_author_actors(@current_user).sync
      authors_out = []

      authors.each do |author|
        author_user = author.visible_actor(@current_user)

        author_actor = Author.new(
          login: author_user&.display_login,
          display_name: author.display_name,
          avatar_url: author_user&.primary_avatar_url || User::AvatarList.default_image_url("gravatar-user-420"),
          path: author_user ? user_path(author_user) : nil,
          is_github: false,
        )
        authors_out << author_actor
      end

      authors_out
    end

    sig { returns(T.nilable(Committer)) }
    def build_committer
      committer = @commit.committer_actor
      return nil unless committer

      committer_user = committer.visible_actor(@current_user)

      Committer.new(
        login: committer_user&.display_login,
        display_name: committer.display_name,
        avatar_url: committer_user&.primary_avatar_url || User::AvatarList.default_image_url("gravatar-user-420"),
        path: committer_user ? user_path(committer_user) : nil,
        is_github: @commit.committed_via_web?,
      )
    end

    sig { returns(PusherResult) }
    def build_pusher
      push = Repositories.domain.pushes.by_commit(
        repository_id: @commit.repository.id,
        repository_network_id: @commit.repository.network_id,
        oid: @commit.sha
      )

      pusher_out = nil
      pushed_at = nil

      if push&.pusher.present?
        push = T.must(push)
        pusher = T.must(push.pusher)
        pusher_login = pusher.display_login
        avatar_url = User.find_by(id: pusher.id)&.primary_avatar_url

        if pusher_login
          pusher_out = Pusher.new(
            login: pusher_login,
            display_name: pusher_login,
            avatar_url: avatar_url || User::AvatarList.default_image_url("gravatar-user-420"),
            path: user_path(pusher),
            is_github: false,
          )
          pushed_at = push.pushed_at&.iso8601
        end
      end

      PusherResult.new(
        pusher: pusher_out,
        pushed_date: pushed_at,
      )
    end
  end
end
