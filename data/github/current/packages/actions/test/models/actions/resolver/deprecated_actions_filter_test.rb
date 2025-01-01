# typed: true
# frozen_string_literal: true

require "test_helper"

class Actions::Resolver::V2::Internal::DeprecatedActionsFilterTest < GitHub::TestCase
  context "actions/upload-artifact and actions/download-artifact" do
    if GitHub.enterprise?
      test "deprecated versions are not blocked on GHES" do
        workflow_repo = create(:repository, from_example: :simple)

        deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false, proxima_fallback_request: false)

        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "1")
        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "1")
      end
    else
      test "deprecated versions are blocked when request is from GH Connect" do
        deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: nil, connect_request: true, proxima_fallback_request: false)

        if GitHub.flipper[:block_artifacts_v1_v2_gh_connect].enabled?
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "1")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "1")
        else
          assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "1")
          assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "1")
        end
      end

      context "blocks any deprecated version" do
        test "deprecated versions are blocked when request is from Proxima Fallback" do
          workflow_repo = create(:repository, from_example: :simple)
          deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false, proxima_fallback_request: true)

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "1")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "1")
        end

        test "using plain refs" do
          workflow_repo = create(:repository, from_example: :simple)

          deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false, proxima_fallback_request: false)

          # Major version 1
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "1")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "1")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "1.5")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "1.5")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "1.5.9")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "1.5.9")

          # Major version 2
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "2")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "2")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "2.5")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "2.5")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "2.5.9")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "2.5.9")
        end

        test "using v-prefixed refs" do
          workflow_repo = create(:repository, from_example: :simple)

          deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false, proxima_fallback_request: false)

          # Lowercase

          # Major version 1
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "v1")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "v1")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "v1.5")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "v1.5")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "v1.5.9")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "v1.5.9")

          # Major version 2
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "v2")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "v2")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "v2.5")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "v2.5")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "v2.5.9")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "v2.5.9")

          # Uppercase

          # Major version 1
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "V1")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "V1")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "V1.5")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "V1.5")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "V1.5.9")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "V1.5.9")

          # Major version 2
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "V2")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "V2")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "V2.5")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "V2.5")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "V2.5.9")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "V2.5.9")
        end

        test "using semver refs" do
          workflow_repo = create(:repository, from_example: :simple)

          deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false, proxima_fallback_request: false)

          # Major version 1
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "1.0.0")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "1.0.0")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "1.5.0")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "1.5.0")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "1.5.9")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "1.5.9")

          # Major version 2
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "2.0.0")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "2.0.0")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "2.5.0")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "2.5.0")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "2.5.9")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "2.5.9")
        end

        test "using partial-semver refs" do
          workflow_repo = create(:repository, from_example: :simple)

          deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false, proxima_fallback_request: false)

          # Lowercase

          # Major version 1
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "1.x")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "1.x")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "1.5.x")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "1.5.x")

          # Major version 2
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "2.x")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "2.x")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "2.5.x")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "2.5.x")

          # Uppercase

          # Major version 1
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "1.X")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "1.X")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "1.5.X")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "1.5.X")

          # Major version 2
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "2.X")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "2.X")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "2.5.X")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "2.5.X")
        end

        test "using v2-preview tag for upload-artifact" do
          workflow_repo = create(:repository, from_example: :simple)

          deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false, proxima_fallback_request: false)

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "v2-preview")
        end

        test "blocking v3 artifacts actions" do
          workflow_repo = create(:repository, from_example: :simple)
          GitHub.flipper[:block_artifacts_v3].enable
          GitHub.flipper[:block_artifacts_v3_exempted].disable

          deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false, proxima_fallback_request: false)

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "3")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "3")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "v3")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "v3")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "V3")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "V3")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "3.1.2")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "3.1.2")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "3.1.10")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "3.1.10")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "3.1.x")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "3.1.x")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "3.1.X")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "3.1.X")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "v3-node20")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "v3-node20")

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "0b7f8abb1508181956e8e162db84b466c27e18ce")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "9bc31d5ccc31df68ecc42ccf4149144866c47d8a")
        end

        test "exempt blocking v3 artifacts actions" do
          workflow_repo = create(:repository, from_example: :simple)
          GitHub.flipper[:block_artifacts_v3].enable
          GitHub.flipper[:block_artifacts_v3_exempted].enable

          deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false, proxima_fallback_request: false)

          assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "3")
          assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "3")
        end

        test "error message" do
          workflow_repo = create(:repository, from_example: :simple)
          GitHub.flipper[:block_artifacts_v3].enable

          deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false, proxima_fallback_request: false)

          v2_deprecation_message = deprecated_actions_filter.error_for_blocked_actions("actions/upload-artifact", "2")
          assert_equal true, v2_deprecation_message.include?("2024-02-13-deprecation-notice-v1-and-v2-of-the-artifact-actions")

          v3_deprecation_message = deprecated_actions_filter.error_for_blocked_actions("actions/upload-artifact", "3")
          assert_equal true, v3_deprecation_message.include?("2024-04-16-deprecation-notice-v3-of-the-artifact-actions")

          v3_deprecation_message = deprecated_actions_filter.error_for_blocked_actions("actions/upload-artifact", "a8a3f3ad30e3422c9c7b888a15615d19a852ae32")
          assert_equal true, v3_deprecation_message.include?("2024-04-16-deprecation-notice-v3-of-the-artifact-actions")

          v3_deprecation_message = deprecated_actions_filter.error_for_blocked_actions("actions/download-artifact", "9782bd6a9848b53b110e712e20e42d89988822b7")
          assert_equal true, v3_deprecation_message.include?("2024-04-16-deprecation-notice-v3-of-the-artifact-actions")
        end

        test "using sha refs" do
          workflow_repo = create(:repository, from_example: :simple)

          deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false, proxima_fallback_request: false)

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "0c366cb4fc8897159c94880f94b55bc716ad6a66")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "726a6dcd0199f578459862705eed35cda05af50b")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "27121b0bdffd731efa15d66772be8dc71245d074")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "e448a9b857ee2131e752b06002bf0e093c65e571")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "3446296876d12d4e3a0f3145a3c87e67bf0a16b5")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "82c141cc518b40d92cc801eee768e7aafc9c2fa2")


          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "18f0f591fbc635562c815484d73b6e8e3980482e")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "f023be2c48cc18debc3bacd34cb396e0295e2869")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "3be87be14a055c47b01d3bd88f8fe02320a9bb60")
          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "158ca71f7c614ae705e79f25522ef4658df18253")
        end
      end

      test "allows non-deprecated versions" do
        workflow_repo = create(:repository, from_example: :simple)

        deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false, proxima_fallback_request: false)

        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "4")
        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "4")

        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "8b95ef7fe9c3bb20d248dd256083429e8c8d7217")
        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "8b95ef7fe9c3bb20d248dd256083429e8c8d7217")
      end

      test "allows non blocked nwos" do
        workflow_repo = create(:repository, from_example: :simple)

        deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false, proxima_fallback_request: false)

        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/cache", ref: "1")
        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/checkout", ref: "2")
      end
    end
  end

  context "actions/cache scheduled for deprecation" do
    if GitHub.enterprise?
      test "deprecated versions are not detected on GHES" do
        workflow_repo = create(:repository, from_example: :simple)

        deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false, proxima_fallback_request: false)

        assert_equal false, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "1")
      end
    else
      test "deprecated versions aren't detected when the request is from GH Connect" do
        workflow_repo = create(:repository, from_example: :simple)

        deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: nil, connect_request: true, proxima_fallback_request: false)

        assert_equal false, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "1")
      end

      context "detects a version scheduled for deprecation" do
        test "using plain refs" do
          workflow_repo = create(:repository, from_example: :simple)

          deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false, proxima_fallback_request: false)

          # Major version 1
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "1")
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "1.5")
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "1.5.9")

          # Major version 2
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "2")
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "2.5")
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "2.5.9")
        end

        test "using v-prefixed refs" do
          workflow_repo = create(:repository, from_example: :simple)

          deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false, proxima_fallback_request: false)

          # Lowercase

          # Major version 1
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "v1")
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "v1.1")
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "v1.1.2")

          # Major version 2
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "v2")
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "v2.1")
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "v2.1.4")

          # Uppercase

          # Major version 1
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "V1")
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "V1.1")
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "V1.1.2")

          # Major version 2
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "V2")
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "V2.1")
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "V2.1.6")
        end

        test "using semver refs" do
          workflow_repo = create(:repository, from_example: :simple)

          deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false, proxima_fallback_request: false)

          # Major version 1
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "1.5.0")
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "1.5.9")
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "1.0.0")

          # Major version 2
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "2.0.0")
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "2.5.0")
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "2.5.9")
        end

        test "using partial-semver refs" do
          workflow_repo = create(:repository, from_example: :simple)

          deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false, proxima_fallback_request: false)

          # Lowercase

          # Major version 1
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "1.x")
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "1.5.x")

          # Major version 2
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "2.x")
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "2.5.x")

          # Uppercase

          # Major version 1
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "1.X")
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "1.5.X")

          # Major version 2
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "2.X")
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "2.5.X")
        end

        test "using sha refs" do
          workflow_repo = create(:repository, from_example: :simple)

          deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false, proxima_fallback_request: false)

          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "c64c572235d810460d0d6876e9c705ad5002b353")
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "0781355a23dac32fd3bac414512f4b903437991a")
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "5ca27f25cb3a0babe750cad7e4fddd3e55f29e9a")
          assert_equal true, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "b8204782bbb5f872091ecc5eb9cb7d004e35b1fa")
        end

        test "allows non-deprecated versions" do
          workflow_repo = create(:repository, from_example: :simple)

          deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false, proxima_fallback_request: false)

          assert_equal false, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "3")
          assert_equal false, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "v3")
          assert_equal false, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "V3")
          assert_equal false, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "3.1.2")
          assert_equal false, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "3.1.x")
          assert_equal false, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "3.1.X")
          assert_equal false, deprecated_actions_filter.action_deprecated?(requested_nwo: "actions/cache", ref: "13aacd865c20de90d75de3b17ebe84f7a17d57d2")
        end
      end
    end
  end
end
