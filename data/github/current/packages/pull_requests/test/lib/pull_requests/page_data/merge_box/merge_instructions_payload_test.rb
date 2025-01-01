# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData
    module MergeBox
      class MergeInstructionsPayloadTest < GitHub::TestCase
        fixtures do
          @owner = create(:user, login: "wiseguy")
          @forker = create(:user, login: "sweetsue")
          @org = create :organization, plan: "bronze", admin: @owner

          @source = create(:private_repository, owner: @owner, name: "source", from_example: :review_comment_fork)
          create(:collaborator, collaborator: @forker, repository: @source)

          @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :review_comment_fork)

          @pull =
            create(:pull_request,
              repository: @source,
              base_repository: @source,
              base_user: @source.owner,
              base_ref: "master",
              head_repository: @fork,
              head_user: @fork.owner,
              head_ref: "topic",
              user: @forker
            )
        end

        test "returns the correct data" do
          data = PullRequests::PageData::MergeBox::MergeInstructionsLoader.load(viewer: @owner, pull_request: @pull)
          payload = PullRequests::PageData::MergeBox::MergeInstructionsPayload.build(data)

          expected_payload = {
            shellSafeBaseRefName: "master",
            shellSafeHeadRefName: "topic",
            shellSafeCrossRepoHeadRefName: "sweetsue-topic",
            shellSafeNamesIncludePlaceholders: false,
            shellEscapingDocsUrl: "https://docs.github.com/get-started/using-git/dealing-with-special-characters-in-branch-and-tag-names",
            resolvingMergeConflictsDocsUrl: "#{GitHub.help_url}/pull-requests/collaborating-with-pull-requests/addressing-merge-conflicts/resolving-a-merge-conflict-using-the-command-line",
            patchUrl: "https://github.com/wiseguy/source/pull/1.patch",
            crossRepoPatchUrl: "https://github.com/wiseguy/source/pull/1.patch",
            pushProtocols: [
              PullRequests::PageData::MergeBox::MergeInstructionsPayload::Protocol.new(isAvailable: true, isDefault: false, stickyUrl: "/users/set_protocol?protocol_selector=ssh&protocol_type=push", url: @fork.ssh_url, protocol: PullRequests::PageData::MergeBox::MergeInstructionsPayload::ProtocolType::SSH), PullRequests::PageData::MergeBox::MergeInstructionsPayload::Protocol.new(isAvailable: true, isDefault: true, stickyUrl: "/users/set_protocol?protocol_selector=http&protocol_type=push", url: @fork.http_url, protocol: PullRequests::PageData::MergeBox::MergeInstructionsPayload::ProtocolType::HTTP)
            ],
          }.as_json

          assert_equal expected_payload, payload.as_json
        end

        test "makes no queries" do
          data = PullRequests::PageData::MergeBox::MergeInstructionsLoader.load(viewer: @owner, pull_request: @pull)
          assert_query_count(0, ignore_feature_flags: true) do
            PullRequests::PageData::MergeBox::MergeInstructionsPayload.build(data)
          end
        end
      end
    end
  end
end
