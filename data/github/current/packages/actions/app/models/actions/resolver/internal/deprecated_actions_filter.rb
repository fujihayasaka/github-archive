# typed: strict
# frozen_string_literal: true

class Actions::Resolver::Internal::DeprecatedActionsFilter

  UPLOAD_ARTIFACT_BLOCKED_REFS = T.let(Set["0c366cb4fc8897159c94880f94b55bc716ad6a66", "726a6dcd0199f578459862705eed35cda05af50b", "27121b0bdffd731efa15d66772be8dc71245d074", "e448a9b857ee2131e752b06002bf0e093c65e571", "3446296876d12d4e3a0f3145a3c87e67bf0a16b5", "v2-preview", "82c141cc518b40d92cc801eee768e7aafc9c2fa2"], T::Set[String])
  DOWNLOAD_ARTIFACT_BLOCKED_REFS = T.let(Set["18f0f591fbc635562c815484d73b6e8e3980482e", "f023be2c48cc18debc3bacd34cb396e0295e2869", "3be87be14a055c47b01d3bd88f8fe02320a9bb60", "158ca71f7c614ae705e79f25522ef4658df18253"], T::Set[String])

  UPLOAD_ARTIFACT_V3_BLOCKED_REFS = T.let(Set["0b7f8abb1508181956e8e162db84b466c27e18ce", "a8a3f3ad30e3422c9c7b888a15615d19a852ae32", "ff15f0306b3f739f7b6fd43fb5d26cd321bd4de5", "3cea5372237819ed00197afe530f5a7ea3e805c8", "83fd05a356d7e2593de66fc9913b3002723633cb"], T::Set[String])
  DOWNLOAD_ARTIFACT_V3_BLOCKED_REFS = T.let(Set["9bc31d5ccc31df68ecc42ccf4149144866c47d8a", "9782bd6a9848b53b110e712e20e42d89988822b7"], T::Set[String])

  CACHE_DEPRECATED_V4_REFS = T.let(Set["13aacd865c20de90d75de3b17ebe84f7a17d57d2", "ab5e6d0c87105b4c9c2047343972218f562e4319", "0c45773b623bea8c8e75f6c82b208c3cf94ea4f9", "2cdf405574d6ef1f33a1d12acccd3ae82f47b3f2", "3624ceb22c1c5a301c8db4169662070a689d9ea8", "6849a6489940f00c2f30c0fb92c6274307ccb58a"], T::Set[String])

  CACHE_DEPRECATED_REFS = T.let(Set[
    "2b250bc32ad02700b996b496c14ac8c2840a2991", # v2.1.8
    "937d24475381cd9c75ae6db12cb4e79714b926ed", # v2.1.7
    "c64c572235d810460d0d6876e9c705ad5002b353", # v2.1.6
    "1a9e2138d905efd099035b49d8b7a3888c653ca8", # v2.1.5
    "26968a09c0ea4f3e233fdddbafd1166051a095f6", # v2.1.4
    "0781355a23dac32fd3bac414512f4b903437991a", # v2.1.3
    "d1255ad9362389eac595a9ae406b8e8cb3331f16", # v2.1.2
    "5ca27f25cb3a0babe750cad7e4fddd3e55f29e9a", # v2.1.1
    "d29c1df198dd38ac88e0ae23a2881b99c2d20e68", # v2.1.0
    "b8204782bbb5f872091ecc5eb9cb7d004e35b1fa", # v2.0.0
    "f5ce41475b483ad7581884324a6eca9f48f8dcc7", # v1.2.1
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

  CACHE_DEPRECATED_V3_REFS = T.let(Set[
    "734d9cb93d6f7610c2400b0f789eaa6f9813e271", # previous v3
    "e12d46a63a90f2fae62d114769bbf2a179198b5c", # v3.3.3
    "704facf57e6136b1bc63b828d79edcd491f0ee84", # v3.3.2
    "88522ab9f39a2ea568f7027eddc7d8d8bc9d59c8", # v3.3.1
    "940f3d7cf195ba83374c77632d1e2cbb2f24ae68", # v3.3.0
    "69d9d449aced6a2ede0bc19182fadc3a0a42d2b0", # v3.2.6
    "6998d139ddd3e68c71e9e398d8e40b71a2f39812", # v3.2.5
    "627f0f41f6904a5b1efbaed9f96d9eb58e92e920", # v3.2.4
    "58c146cc91c5b9e778e71775dfe9bf1442ad9a12", # v3.2.3
    "4723a57e26efda3a62cbde1812113b730952852d", # v3.2.2
    "c1a5de879eb890d062a85ee0252d6036480b1fe2", # v3.2.1
    "c17f4bf4666a8001b1a45c09eb7a485c41aa64c3", # v3.2.0
    "ed5e94a5f508b86f7084d217cef20fb6a212ad58", # v3.2.0-beta.1
    "a2137c625cf42636129d84ff5e5f0e8beac11a08", # v3.1.0-beta.3
    "f33ca902b8d71720710197bdcfc32e40ccab65f9", # v3.1.0-beta.2
    "4d2f35c1eb62d0810cd81a206982cdc8acc4e318", # v3.1.0-beta.1
    "9b0c1fce7a93df8e3bb8926b0d6e9d89e92f20a7", # v3.0.11
    "56461b9eb0f8438fd15c7a9968e3c9ebb18ceff1", # v3.0.10
    "ac8075791e805656e71b4ba23325ace9e3421120", # v3.0.9
    "fd5de65bc895cf536527842281bea11763fefd77", # v3.0.8
    "a7c34adf76222e77931dedbf4a45b2e4648ced19", # v3.0.7
    "f4278025ab0f432ce369118909e46deec636f50c", # v3.0.6
    "0865c47f36e68161719c5b124609996bb5c40129", # v3.0.5
    "c3f1317a9e7b1ef106c153ac8c0f00fed3ddbc0d", # v3.0.4
    "30f413bfed0a2bc738fdfd409e5a9e96b24545fd", # v3.0.3
    "48af2dc4a9e8278b89d7fa154b955c30c6aaab09", # v3.0.2
    "136d96b4aee02b1f0de3ba493b1d47135042d9c0", # v3.0.1
    "4b0cf6cc4619e737324ddfcec08fff2413359514"  # v3.0.0
  ], T::Set[String])

  CACHE_V3_LEGACY_REF_PATTERN = T.let(Regexp.new('\A[vV]?3\.[0-3](\.\d+(-[\w\.]+)?|\S*)\z').freeze, Regexp)
  CACHE_V4_LEGACY_REF_PATTERN = T.let(Regexp.new('\A[vV]?4\.[0-1](\.\d+|\.|\S*)?\z').freeze, Regexp)

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
  def ref_match_cache_v3_v4?(ref:)
    # with the upcoming deprecation of Artifact Cache, all versions prior to 4.2.0 and 3.4.0 will eventually result in workflow failures
    CACHE_V3_LEGACY_REF_PATTERN.match?(ref) || CACHE_V4_LEGACY_REF_PATTERN.match?(ref) || CACHE_DEPRECATED_V3_REFS.include?(ref) || CACHE_DEPRECATED_V4_REFS.include?(ref)
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

    if GitHub.flipper[:block_artifacts_v3].enabled?(@workflow_repo.owner) || GitHub.flipper[:block_artifacts_v3].enabled?(@workflow_repo)
      return ref_match_artifact_v3?(ref:)
    end

    false
  end

  sig do
    params(
      requested_nwo: String,
      ref: String,
    ).returns(T::Boolean)
  end
  def cache_deprecated_refs_blocked?(requested_nwo:, ref:)
    return false unless @workflow_repo&.feature_enabled?(:actions_block_deprecated_actions_cache_refs)
    return false if @connect_request
    return false if @proxima_fallback_request
    CACHE_DEPRECATED_REFS.include?(ref) || ref_match?(ref:) || ref_match_cache_v3_v4?(ref:)
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

    # we should check this flag for actifacts only
    if GitHub.flipper[:exempt_proxima_staffship_from_blocked_actions].enabled? && @proxima_fallback_request
      GitHub.dogstats.increment(
        "actions.proxima.exempted_from_blocked_actions"
      )
      return false
    end

    case requested_nwo
    when "actions/upload-artifact"
      UPLOAD_ARTIFACT_BLOCKED_REFS.include?(ref) || ref_match?(ref:) || artifacts_v3_blocked?(ref:)
    when "actions/download-artifact"
      DOWNLOAD_ARTIFACT_BLOCKED_REFS.include?(ref) || ref_match?(ref:) || artifacts_v3_blocked?(ref:)
    when "actions/cache"
      cache_deprecated_refs_blocked?(requested_nwo:, ref:)
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
      CACHE_DEPRECATED_REFS.include?(ref) || ref_match?(ref:) || ref_match_cache_v3_v4?(ref:)
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
    if ref_match_artifact_v3?(ref:) && requested_nwo == "actions/upload-artifact" || requested_nwo == "actions/download-artifact"
      return "This request has been automatically failed because it uses a deprecated version of `#{requested_nwo}: #{ref}`. Learn more: #{GitHub.blog_url}/changelog/2024-04-16-deprecation-notice-v3-of-the-artifact-actions/"
    elsif requested_nwo == "actions/cache" && cache_deprecated_refs_blocked?(requested_nwo:, ref:)
      return "This request has been automatically failed because it uses a deprecated version of `#{requested_nwo}: #{ref}`. Please update your workflow to use v3/v4 of #{requested_nwo} to avoid interruptions. Learn more: #{GitHub.blog_url}/changelog/2024-12-05-notice-of-upcoming-releases-and-breaking-changes-for-github-actions/#actions-cache-v1-v2-and-actions-toolkit-cache-package-closing-down"
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
    "Your workflow is using a version of #{requested_nwo} that is scheduled for deprecation, #{requested_nwo}@#{ref}. Please update your workflow to use either v3 or v4 of #{requested_nwo} to avoid interruptions. Learn more: #{GitHub.blog_url}/changelog/2024-12-05-notice-of-upcoming-releases-and-breaking-changes-for-github-actions/#actions-cache-v1-v2-and-actions-toolkit-cache-package-closing-down"
  end
end
