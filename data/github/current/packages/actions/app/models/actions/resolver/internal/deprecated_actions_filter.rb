# typed: strict
# frozen_string_literal: true

class Actions::Resolver::Internal::DeprecatedActionsFilter
  extend T::Sig

  UPLOAD_ARTIFACT_BLOCKED_REFS = T.let(Set["0c366cb4fc8897159c94880f94b55bc716ad6a66", "726a6dcd0199f578459862705eed35cda05af50b", "27121b0bdffd731efa15d66772be8dc71245d074", "e448a9b857ee2131e752b06002bf0e093c65e571", "3446296876d12d4e3a0f3145a3c87e67bf0a16b5", "v2-preview", "82c141cc518b40d92cc801eee768e7aafc9c2fa2"], T::Set[String])
  DOWNLOAD_ARTIFACT_BLOCKED_REFS = T.let(Set["18f0f591fbc635562c815484d73b6e8e3980482e", "f023be2c48cc18debc3bacd34cb396e0295e2869", "3be87be14a055c47b01d3bd88f8fe02320a9bb60", "158ca71f7c614ae705e79f25522ef4658df18253"], T::Set[String])

  sig do
    params(
      workflow_repo: T.nilable(Repository),
      connect_request: T::Boolean
    ).void
  end
  def initialize(workflow_repo:, connect_request:)
    @connect_request = connect_request
    @workflow_repo = workflow_repo
  end

  sig do
    params(
      ref: String,
    ).returns(T::Boolean)
  end
  def ref_match?(ref:)
    # will match any version that starts with 1. or 2.
    # e.g. v1, v1.0, v1.0.0, 1, 1.0, 1.0.0, v2, v2.0, v2.0.0, 2, 2.0, 2.0.0
    pattern = Regexp.new('\A[vV]{0,1}([1-2]){1}(\.\S)*$').freeze
    pattern.match?(ref)
  end

  sig do
    params(
      requested_nwo: String,
      ref: String,
    ).returns(T::Boolean)
  end
  def action_blocked?(requested_nwo:, ref:)
    return false if GitHub.enterprise? # GHES onbox resolution is not blocked
    return false if @connect_request # GH Connect resolution is not blocked
    return false unless @workflow_repo&.feature_enabled?(:block_artifacts_v1_v2_dotcom)

    case requested_nwo
    when "actions/upload-artifact"
      UPLOAD_ARTIFACT_BLOCKED_REFS.include?(ref) || ref_match?(ref:)
    when "actions/download-artifact"
      DOWNLOAD_ARTIFACT_BLOCKED_REFS.include?(ref) || ref_match?(ref:)
    else
      false
    end
  end

  sig do
    params(
      requested_nwo: String,
      ref: String,
    ).returns(String)
  end
  def error_for_blocked_actions(requested_nwo, ref)
    "This request has been automatically failed because it uses a deprecated version of `#{requested_nwo}: #{ref}`. Learn more: #{GitHub.blog_url}/changelog/2024-02-13-deprecation-notice-v1-and-v2-of-the-artifact-actions/"
  end
end
