# typed: strict
# frozen_string_literal: true

module CopilotSpaces::PageData::CopilotSpace
  class UrlValidationPayload
    sig { params(metadata: CopilotSpaceResource::Metadata).returns(T::Hash[Symbol, T.untyped]) }
    def self.call(metadata)
      new.call(metadata)
    end

    sig { params(metadata: CopilotSpaceResource::Metadata).returns(T::Hash[Symbol, T.untyped]) }
    def call(metadata)
      case metadata
      when CopilotSpaceResource::GitHubFileMetadata
        build_github_file_payload(metadata)
      when CopilotSpaceResource::GitHubIssueMetadata
        build_github_issue_payload(metadata)
      when CopilotSpaceResource::GitHubPullRequestMetadata
        build_github_pull_request_payload(metadata)
      else
        raise NotImplementedError
      end
    end

    private

    sig { params(metadata: CopilotSpaceResource::GitHubFileMetadata).returns(T::Hash[Symbol, T.untyped]) }
    def build_github_file_payload(metadata)
      {
        type: CopilotSpaceResource::Constants::GITHUB_FILE,
        filePath: metadata.file_path,
        nwo: metadata.repository&.name_with_display_owner,
        repositoryId: metadata.repository&.id,
        fileExists: true,
        sha: metadata.sha || metadata.repository&.default_branch,
      }
    end

    sig { params(metadata: CopilotSpaceResource::GitHubIssueMetadata).returns(T::Hash[Symbol, T.untyped]) }
    def build_github_issue_payload(metadata)
      {
        type: CopilotSpaceResource::Constants::GITHUB_ISSUE,
        number: metadata.number,
        url: metadata.issue&.url,
        nwo: metadata.repository&.name_with_display_owner,
        title: metadata.issue&.title,
        repositoryId: metadata.repository&.id,
      }
    end

    sig { params(metadata: CopilotSpaceResource::GitHubPullRequestMetadata).returns(T::Hash[Symbol, T.untyped]) }
    def build_github_pull_request_payload(metadata)
      {
        type: CopilotSpaceResource::Constants::GITHUB_PULL_REQUEST,
        number: metadata.number,
        url: metadata.pull_request&.url,
        nwo: metadata.repository&.name_with_display_owner,
        title: metadata.pull_request&.title,
        repositoryId: metadata.repository&.id,
      }
    end
  end
end
