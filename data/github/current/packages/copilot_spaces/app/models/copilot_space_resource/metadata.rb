# typed: true
# frozen_string_literal: true

class CopilotSpaceResource::Metadata
  extend T::Helpers

  abstract!

  sig { abstract.params(json: T.untyped).returns(T.attached_class) }
  def self.from_json(json); end

  # Converts the metadata to a Twirp-compatible format.
  sig do
    abstract.returns(
      T.nilable(T.any(
        MonolithTwirp::Copilotapi::CustomCopilots::V1::GitHubFileMetadata,
        MonolithTwirp::Copilotapi::CustomCopilots::V1::FreeTextMetadata,
        MonolithTwirp::Copilotapi::CustomCopilots::V1::UploadedTextFileMetadata,
        MonolithTwirp::Copilotapi::CustomCopilots::V1::GitHubIssueMetadata,
        MonolithTwirp::Copilotapi::CustomCopilots::V1::GitHubPullRequestMetadata,
        MonolithTwirp::Copilotapi::CustomCopilots::V1::MediaContentMetadata,
        MonolithTwirp::Copilotapi::CustomCopilots::V1::RepositoryMetadata
      ))
    )
  end
  def to_copilot_config_twirp; end

  sig { overridable.returns(T::Hash[Symbol, T.untyped]) }
  def to_url_validation_payload
    raise NotImplementedError
  end
end
