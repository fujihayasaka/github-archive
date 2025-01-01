# typed: true
# frozen_string_literal: true
require "test_helper"

class Actions::Resolver::V2::Internal::DeprecatedActionsFilterTest < GitHub::TestCase
  context "actions/upload-artifact and actions/download-artifact" do
    if GitHub.enterprise?
      test "deprecated versions are not blocked on GHES" do
        GitHub.flipper[:block_artifacts_v1_v2_dotcom].enable

        workflow_repo = create(:repository, from_example: :simple)

        deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false)

        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "1")
        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "1")
      end
    else
      test "deprecated versions are not blocked when feature flag is disabled" do
        GitHub.flipper[:block_artifacts_v1_v2_dotcom].disable

        workflow_repo = create(:repository, from_example: :simple)

        deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false)

        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "1")
        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "1")
      end

      test "feature flag can be enabled on a per workflow-repo basis" do
        GitHub.flipper[:block_artifacts_v1_v2_dotcom].disable

        workflow_repo = create(:repository, from_example: :simple)
        other_workflow_repo = create(:repository, from_example: :simple)

        GitHub.flipper[:block_artifacts_v1_v2_dotcom].enable(workflow_repo)

        deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false)
        other_deployed_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: other_workflow_repo, connect_request: false)

        assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "1")
        assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "1")

        assert_equal false, other_deployed_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "1")
        assert_equal false, other_deployed_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "1")
      end

      test "deprecated versions are not blocked when request is from GH Connect or proxima fallback" do
        GitHub.flipper[:block_artifacts_v1_v2_dotcom].enable

        workflow_repo = create(:repository, from_example: :simple)

        deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: nil, connect_request: true)

        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "1")
        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "1")
      end

      context "blocks any deprecated version" do
        test "using plain refs" do
          GitHub.flipper[:block_artifacts_v1_v2_dotcom].enable

          workflow_repo = create(:repository, from_example: :simple)

          deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false)

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
          GitHub.flipper[:block_artifacts_v1_v2_dotcom].enable

          workflow_repo = create(:repository, from_example: :simple)

          deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false)

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
          GitHub.flipper[:block_artifacts_v1_v2_dotcom].enable

          workflow_repo = create(:repository, from_example: :simple)

          deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false)

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
          GitHub.flipper[:block_artifacts_v1_v2_dotcom].enable

          workflow_repo = create(:repository, from_example: :simple)

          deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false)

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
          GitHub.flipper[:block_artifacts_v1_v2_dotcom].enable

          workflow_repo = create(:repository, from_example: :simple)

          deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false)

          assert_equal true, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "v2-preview")
        end

        test "using sha refs" do
          GitHub.flipper[:block_artifacts_v1_v2_dotcom].enable

          workflow_repo = create(:repository, from_example: :simple)

          deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false)

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
        GitHub.flipper[:block_artifacts_v1_v2_dotcom].enable

        workflow_repo = create(:repository, from_example: :simple)

        deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false)

        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "3")
        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "3")

        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "v3")
        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "v3")

        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "V3")
        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "V3")

        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "3.1.2")
        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "3.1.2")

        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "3.1.x")
        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "3.1.x")

        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "3.1.X")
        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "3.1.X")

        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/upload-artifact", ref: "8b95ef7fe9c3bb20d248dd256083429e8c8d7217")
        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/download-artifact", ref: "8b95ef7fe9c3bb20d248dd256083429e8c8d7217")
      end

      test "allows non blocked nwos" do
        GitHub.flipper[:block_artifacts_v1_v2_dotcom].enable

        workflow_repo = create(:repository, from_example: :simple)

        deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false)

        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/cache", ref: "1")
        assert_equal false, deprecated_actions_filter.action_blocked?(requested_nwo: "actions/checkout", ref: "2")
      end
    end
  end
end
