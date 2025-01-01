# typed: strict
# frozen_string_literal: true

module PullRequests::PageData
  class CommitsSerializer
    class ActorData < T::Struct
      const :avatarUrl, String
      const :displayName, String
      const :login, T.nilable(String)
      const :path, T.nilable(String)
      const :isGitHub, T::Boolean
    end

    class CommitData < T::Struct
      const :authoredDate, Time
      const :authors, T::Array[ActorData]
      const :bodyMessageHtml, String
      const :committedDate, Time
      const :committer, T.nilable(ActorData)
      const :committerAttribution, T::Boolean
      const :oid, String
      const :shortMessage, String
      const :shortMessageMarkdown, T.nilable(String)
      const :shortMessageMarkdownLink, String
      const :url, String
    end

    class CommitGroupData < T::Struct
      const :commits, T::Array[CommitData]
      const :title, String
    end

    class MetadataData < T::Struct
      # this will be removed in a future PR
      const :aliveChannel, String
      const :deferredCommitsDataUrl, String
    end

    class RepositoryData < T::Struct
      const :defaultBranch, String
      const :name, String
      const :ownerLogin, String
    end

    class CommitsData < T::Struct
      const :commitGroups, T::Array[CommitGroupData]
      const :metadata, MetadataData
      const :repository, RepositoryData
      const :timeOutMessage, String
      const :truncated, T::Boolean
    end

    sig do
      params(
        alive_channel: String,
        commit_groups: T::Array[T::Hash[Symbol, T.untyped]],
        deferred_commits_data_url: String,
        repository: Repository,
        time_out_message: String,
        truncated: T::Boolean,
      ).void
    end
    def initialize(
      alive_channel:,
      commit_groups:,
      deferred_commits_data_url:,
      repository:,
      time_out_message:,
      truncated:
    )
      @alive_channel = alive_channel
      @commit_groups = commit_groups
      @deferred_commits_data_url = deferred_commits_data_url
      @repository = repository
      @time_out_message = time_out_message
      @truncated = truncated
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def to_hash
      CommitsData.new(
        commitGroups: @commit_groups.map do |commit_group|
          CommitGroupData.new(
            commits: commit_group[:commits].map do |commit|
              CommitData.new(
                authoredDate: commit[:authoredDate],
                authors: commit[:authors].map do |author|
                  ActorData.new(
                    avatarUrl: author[:avatarUrl],
                    displayName: author[:displayName],
                    login: author[:login],
                    path: author[:path],
                    isGitHub: false,
                  )
                end,
                bodyMessageHtml: commit[:bodyMessageHtml],
                committer: ActorData.new(
                  avatarUrl: commit[:committer][:avatarUrl],
                  displayName: commit[:committer][:displayName],
                  login: commit[:committer][:login],
                  path: commit[:committer][:path],
                  isGitHub: commit[:committer][:isGitHub],
                ),
                committedDate: commit[:committedDate],
                committerAttribution: commit[:committerAttribution],
                oid: commit[:oid],
                shortMessage: commit[:shortMessage],
                shortMessageMarkdown: commit[:shortMessageMarkdown],
                shortMessageMarkdownLink: commit[:shortMessageMarkdownLink],
                url: commit[:url],
              )
            end,
            title: commit_group[:title],
          )
        end,
        metadata: MetadataData.new(
          aliveChannel: @alive_channel,
          deferredCommitsDataUrl: @deferred_commits_data_url,
        ),
        repository: RepositoryData.new(
          defaultBranch: @repository.default_branch,
          name: @repository.name,
          ownerLogin: @repository.owner_display_login,
        ),
        timeOutMessage: @time_out_message,
        truncated: @truncated,
      ).as_json
    end
  end
end
