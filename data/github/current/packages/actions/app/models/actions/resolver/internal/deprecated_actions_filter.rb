# typed: strict
# frozen_string_literal: true

class Actions::Resolver::Internal::DeprecatedActionsFilter

  UPLOAD_ARTIFACT_BLOCKED_REFS = T.let(Set["0c366cb4fc8897159c94880f94b55bc716ad6a66", "726a6dcd0199f578459862705eed35cda05af50b", "27121b0bdffd731efa15d66772be8dc71245d074", "e448a9b857ee2131e752b06002bf0e093c65e571", "3446296876d12d4e3a0f3145a3c87e67bf0a16b5", "v2-preview", "82c141cc518b40d92cc801eee768e7aafc9c2fa2"], T::Set[String])
  DOWNLOAD_ARTIFACT_BLOCKED_REFS = T.let(Set["18f0f591fbc635562c815484d73b6e8e3980482e", "f023be2c48cc18debc3bacd34cb396e0295e2869", "3be87be14a055c47b01d3bd88f8fe02320a9bb60", "158ca71f7c614ae705e79f25522ef4658df18253"], T::Set[String])

  UPLOAD_ARTIFACT_V3_BLOCKED_REFS = T.let(Set["0b7f8abb1508181956e8e162db84b466c27e18ce", "a8a3f3ad30e3422c9c7b888a15615d19a852ae32", "ff15f0306b3f739f7b6fd43fb5d26cd321bd4de5", "3cea5372237819ed00197afe530f5a7ea3e805c8", "83fd05a356d7e2593de66fc9913b3002723633cb"], T::Set[String])
  DOWNLOAD_ARTIFACT_V3_BLOCKED_REFS = T.let(Set["9bc31d5ccc31df68ecc42ccf4149144866c47d8a", "9782bd6a9848b53b110e712e20e42d89988822b7"], T::Set[String])

  # List of SHAs that are scheduled for deprecation
  CACHE_DEPRECATED_REFS = T.let(Set[
    "937d24475381cd9c75ae6db12cb4e79714b926ed", # v2.1.7
    "c64c572235d810460d0d6876e9c705ad5002b353", # v2.1.6
    "1a9e2138d905efd099035b49d8b7a3888c653ca8", # v2.1.5
    "26968a09c0ea4f3e233fdddbafd1166051a095f6", # v2.1.4
    "0781355a23dac32fd3bac414512f4b903437991a", # v2.1.3
    "d1255ad9362389eac595a9ae406b8e8cb3331f16", # v2.1.2
    "5ca27f25cb3a0babe750cad7e4fddd3e55f29e9a", # v2.1.1
    "d29c1df198dd38ac88e0ae23a2881b99c2d20e68", # v2.1.0
    "b8204782bbb5f872091ecc5eb9cb7d004e35b1fa", # v2.0.0
    "d9747005de0f7240e5d35a68dca96b3f41b8b340", # v1.2.0
    "70655ec8323daeeaa7ef06d7c56e1b9191396cbe", # v1.1.2
    "fe1055e9d167ff6b0247ec54ca5851b2701fe95c", # v1.1.1
    "a505c2e7a6652a1d5727baf1c2dc5a5b2d1ecc60", # v1.1.0
    "cffae9552bb9f84b9812c1ee9ea2e3c0a70a797e", # v1.0.3
    "44543250bd1b1d68b70b6e9949c2a11f5b11d990", # v1.0.2
    "86dff562ab522d4b40945cd4cd51c5d4b4b40cbc", # v1.0.1
    "9d8c7b4041799ff4995821122f3c4ce8934a36b7", # v1.0.0
    "0da99ad140d4e8eb671003569d4e357fa825ff44", # v0.0.2
    "e7ad80454a6127bc11c0f89f007eff9fecd8c4f7"  # v0.0.1
  ], T::Set[String])

  ACTIONS_V3_REF_PATTERN = T.let(Regexp.new('\A[vV]{0,1}(3){1}(\.|-|\z)\S*\z').freeze, Regexp)

  sig do
    params(
      workflow_repo: T.nilable(Repository),
      connect_request: T::Boolean,
      proxima_fallback_request: T::Boolean
    ).void
  end
  def initialize(workflow_repo:, connect_request:, proxima_fallback_request:)
    @connect_request = connect_request
    @workflow_repo = workflow_repo
    @proxima_fallback_request = proxima_fallback_request
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
      ref: String,
    ).returns(T::Boolean)
  end
  def ref_match_artifact_v3?(ref:)
    # will match any version that starts with 3 or it's a known v3 SHA
    ACTIONS_V3_REF_PATTERN.match?(ref) || UPLOAD_ARTIFACT_V3_BLOCKED_REFS.include?(ref) || DOWNLOAD_ARTIFACT_V3_BLOCKED_REFS.include?(ref)
  end

  sig do
    params(
      ref: String,
    ).returns(T::Boolean)
  end
  def artifacts_v3_blocked?(ref:)
    # no workflow_repo for GitHub Connect
    exempted = GitHub.enterprise? || @connect_request || @workflow_repo.nil? || GitHub.flipper[:block_artifacts_v3_exempted].enabled?(@workflow_repo.owner) || GitHub.flipper[:block_artifacts_v3_exempted].enabled?(@workflow_repo)
    return false if exempted

    return false unless GitHub.flipper[:block_artifacts_v3].enabled?(@workflow_repo)

    ref_match_artifact_v3?(ref:)
  end

  sig do
    params(
      requested_nwo: String,
      ref: String,
    ).returns(T::Boolean)
  end
  def action_blocked?(requested_nwo:, ref:)
    return false if GitHub.enterprise? # GHES onbox resolution is not blocked
    return false if @connect_request && !GitHub.flipper[:block_artifacts_v1_v2_gh_connect].enabled?

    case requested_nwo
    when "actions/upload-artifact"
      UPLOAD_ARTIFACT_BLOCKED_REFS.include?(ref) || ref_match?(ref:) || artifacts_v3_blocked?(ref:)
    when "actions/download-artifact"
      DOWNLOAD_ARTIFACT_BLOCKED_REFS.include?(ref) || ref_match?(ref:) || artifacts_v3_blocked?(ref:)
    else
      false
    end
  end

  sig do
    params(
      requested_nwo: String,
      ref: String,
    ).returns(T::Boolean)
  end
  def action_deprecated?(requested_nwo:, ref:)
    return false if GitHub.enterprise?
    return false if @connect_request
    return false if @proxima_fallback_request

    case requested_nwo
    when "actions/cache"
      CACHE_DEPRECATED_REFS.include?(ref) || ref_match?(ref:)
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
    if ref_match_artifact_v3?(ref:)
      return "This request has been automatically failed because it uses a deprecated version of `#{requested_nwo}: #{ref}`. Learn more: #{GitHub.blog_url}/changelog/2024-04-16-deprecation-notice-v3-of-the-artifact-actions/"
    end
    "This request has been automatically failed because it uses a deprecated version of `#{requested_nwo}: #{ref}`. Learn more: #{GitHub.blog_url}/changelog/2024-02-13-deprecation-notice-v1-and-v2-of-the-artifact-actions/"
  end

  sig do
    params(
      requested_nwo: String,
      ref: String,
    ).returns(String)
  end
  def warning_for_deprecating_actions(requested_nwo, ref)
    "Your workflow is using a version of #{requested_nwo} that is scheduled for deprecation, #{requested_nwo}@#{ref}. Please update your workflow to use the latest version of #{requested_nwo} to avoid interruptions. Learn more: #{GitHub.blog_url}/changelog/2024-09-16-notice-of-upcoming-deprecations-and-changes-in-github-actions-services/"
  end
end
