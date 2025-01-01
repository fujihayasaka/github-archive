# typed: true
# frozen_string_literal: true

require "test_helper"
module PullRequests
  module PageData
    module MergeBox
      class MergeRequirementsPayloadTest < GitHub::TestCase
        fixtures do
          @owner = create(:user, login: "wiseguy")
          @forker = create(:user, :verified, login: "forker")
          @rando  = create(:user)

          @source = create(:repository, owner: @owner, name: "source", from_example: :pr_mergeability)
          @source.add_member @forker, action: :write

          @fork = create(:fork_repository, forker: @forker, fork_repo: @source, create_owner: true, from_example: :pr_mergeability)

          @issue = create(:issue, user: @owner, repository: @source, title: "A Title")
          @pull =
            create(:pull_request,
              repository: @source,
              base_repository: @source,
              base_user: @source.owner,
              base_ref: "master",
              head_repository: @source,
              head_user: @source.owner,
              head_ref: "ahead",
              issue: @issue,
              user: @owner
            )

          @pull_behind_and_conflicted =
            create(:pull_request,
              repository: @source,
              base_repository: @source,
              base_user: @source.owner,
              base_ref: "master",
              head_repository: @source,
              head_user: @source.owner,
              head_ref: "behind-and-conflicted",
              user: @owner,
              title: "PR that is behind base branch with conflicts",
              body: "can't be nil",
              )

          @pull.create_merge_commit

          ruleset = create(:repository_ruleset, :targets_branch, qualified_ref_name: "refs/heads/master", source: @source)
          create(:repository_rule_configuration, :update, repository_ruleset: ruleset)
        end

        context "#call" do
          test "builds and returns a MergeRequirementsPayload object" do
            merge_requirements_data = PullRequests::PageData::MergeBox::MergeRequirementsLoader.load(viewer: @pull.user, pull_request: @pull, repository: @source, merge_action: nil, merge_method: nil, bypass_requirements: true)
            actual_payload = PullRequests::PageData::MergeBox::MergeRequirementsPayload.call(merge_requirements_data)

            assert_equal "UNMERGEABLE", actual_payload.as_json["state"]
            assert_equal @pull.user.git_author_email, actual_payload.as_json["defaultCommitAuthorEmail"]
            assert_equal @pull.default_merge_commit_title, actual_payload.as_json["commitMessageHeadline"]
            assert_equal @pull.default_merge_commit_message, actual_payload.as_json["commitMessageBody"]
            assert_no_queries do
              PullRequests::PageData::MergeBox::MergeRequirementsPayload.call(merge_requirements_data)
            end
          end

          test "can represent all possible MergeConditionTypes" do
            MergeConditions::Evaluator::CONDITIONS.each do |condition_class|
              type = condition_class.name&.demodulize&.underscore&.upcase
              assert_nothing_raised do
                PullRequests::PageData::MergeBox::MergeRequirementsPayload::MergeConditionType.deserialize(type)
              end
            end
          end

          test "can represent all possible MergeConditionResults" do
            MergeConditions::EvaluationResult.any_instance.stubs(:result).returns(:passed)
            merge_requirements_data = PullRequests::PageData::MergeBox::MergeRequirementsLoader.load(viewer: @pull.user, pull_request: @pull, repository: @source, merge_action: nil, merge_method: nil, bypass_requirements: true)
            actual_payload = PullRequests::PageData::MergeBox::MergeRequirementsPayload.call(merge_requirements_data)

            assert condition = actual_payload.as_json["conditions"].find { |c| c["type"] == "PULL_REQUEST_RULES" }
            assert_equal "PASSED", condition["result"]

            MergeConditions::EvaluationResult.any_instance.stubs(:result).returns(:failed)
            merge_requirements_data = PullRequests::PageData::MergeBox::MergeRequirementsLoader.load(viewer: @pull.user, pull_request: @pull, repository: @source, merge_action: nil, merge_method: nil, bypass_requirements: true)
            actual_payload = PullRequests::PageData::MergeBox::MergeRequirementsPayload.call(merge_requirements_data)

            assert condition = actual_payload.as_json["conditions"].find { |c| c["type"] == "PULL_REQUEST_RULES" }
            assert_equal "FAILED", condition["result"]
          end

          test "turns URLs in condition messages into links" do
            merge_requirements_data = PullRequests::PageData::MergeBox::MergeRequirementsLoader.load(viewer: @pull.user, pull_request: @pull, repository: @source, merge_action: nil, merge_method: nil, bypass_requirements: true)
            merge_requirements_data&.conditions && merge_requirements_data.conditions.find { |c| c.type == MergeRequirementsPayload::MergeConditionType::PullRequestRules }&.message = "Visit https://google.com"
            actual_payload = PullRequests::PageData::MergeBox::MergeRequirementsPayload.call(merge_requirements_data)

            assert condition = actual_payload.as_json["conditions"].find { |c| c["type"] == "PULL_REQUEST_RULES" }
            assert condition["message"].include?("<a href=")
          end

          test "escapes HTML characters being put into condition messages" do
            merge_requirements_data = PullRequests::PageData::MergeBox::MergeRequirementsLoader.load(viewer: @pull.user, pull_request: @pull, repository: @source, merge_action: nil, merge_method: nil, bypass_requirements: true)
            merge_requirements_data&.conditions && merge_requirements_data.conditions.find { |c| c.type == MergeRequirementsPayload::MergeConditionType::PullRequestRules }&.message = "I am being very <span>sneaky</span>"
            actual_payload = PullRequests::PageData::MergeBox::MergeRequirementsPayload.call(merge_requirements_data)

            assert condition = actual_payload.as_json["conditions"].find { |c| c["type"] == "PULL_REQUEST_RULES" }
            assert_equal "<div>I am being very &lt;span&gt;sneaky&lt;/span&gt;</div>", condition["message"]
          end
        end
      end
    end
  end
end
