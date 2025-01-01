# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module PageData
    module MergeBox
      class MergeRequirementsLoaderTest < GitHub::TestCase
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
          example_repo_snapshot
        end

        setup do
          example_repo_restore
        end

        test "returns expected data, when a PR is open" do
          actual_data = PullRequests::PageData::MergeBox::MergeRequirementsLoader.load(pull_request: @pull, viewer: @forker, repository: @source, merge_action: nil, merge_method: nil, bypass_requirements: false)

          assert_equal :unknown, T.must(actual_data).state
          assert_equal @pull.user.git_author_email, T.must(actual_data).commit_author_email
          assert_equal @pull.default_merge_commit_message, T.must(actual_data).commit_message_body
          assert_equal @pull.default_merge_commit_title, T.must(actual_data).commit_message_headline
          assert_equal 6, T.must(actual_data).conditions.count
        end


        test "uses fallback value when #async_default_merge_message_parts query fails" do
          PullRequest::MergeRequirements.any_instance.stubs(:async_default_merge_message_parts).raises(ActiveRecord::ActiveRecordError.new)

          data = PullRequests::PageData::MergeBox::MergeRequirementsLoader.load(pull_request: @pull, viewer: @owner, repository: @source, merge_action: nil, merge_method: nil, bypass_requirements: false)

          assert_nil T.must(data).commit_message_body
          assert_nil T.must(data).commit_message_headline
        end

        test "uses fallback value when #async_state query fails" do
          PullRequest::MergeRequirements.any_instance.stubs(:async_state).raises(ActiveRecord::ActiveRecordError.new)

          data = PullRequests::PageData::MergeBox::MergeRequirementsLoader.load(pull_request: @pull, viewer: @owner, repository: @source, merge_action: nil, merge_method: nil, bypass_requirements: false)

          assert_equal :unknown, T.must(data).state
        end

        test "returns nil if PR state closed" do
          T.must(@pull.issue).update(state: "closed")
          @pull.reload
          assert @pull.closed?

          data = PullRequests::PageData::MergeBox::MergeRequirementsLoader.load(pull_request: @pull, viewer: @owner, repository: @source, merge_action: nil, merge_method: nil, bypass_requirements: false)
          assert_nil data
        end

        test "returns nil if PR state merged" do
          @pull.merge
          assert @pull.merged?

          data = PullRequests::PageData::MergeBox::MergeRequirementsLoader.load(pull_request: @pull, viewer: @owner, repository: @source, merge_action: nil, merge_method: nil, bypass_requirements: false)
          assert_nil data
        end

        context "merge method is rebase" do
          test "returns nil for commit message body and headline" do
            data = PullRequests::PageData::MergeBox::MergeRequirementsLoader.load(pull_request: @pull, viewer: @owner, repository: @source, merge_action: nil, merge_method: "rebase", bypass_requirements: false)

            assert_nil T.must(data).commit_message_body
            assert_nil T.must(data).commit_message_headline
          end
        end

        context "merge method is squash" do
          test "returns commit message body and headline" do
            data = PullRequests::PageData::MergeBox::MergeRequirementsLoader.load(pull_request: @pull, viewer: @owner, repository: @source, merge_action: nil, merge_method: "squash", bypass_requirements: false)

            refute_nil T.must(data).commit_message_body
            refute_nil T.must(data).commit_message_headline
          end

          test "always returns the pull's author email" do
            data = PullRequests::PageData::MergeBox::MergeRequirementsLoader.load(pull_request: @pull, viewer: @owner, repository: @source, merge_action: nil, merge_method: "SQUASH", bypass_requirements: false)

            refute_nil T.must(data).commit_author_email
            assert_equal @pull.user.git_author_email, T.must(data).commit_author_email
          end

          test "returns the commit author's private email address when keep email address private is enabled" do
            @pull.owner.primary_user_email.toggle_visibility
            refute @pull.owner.primary_user_email.public?

            data = PullRequests::PageData::MergeBox::MergeRequirementsLoader.load(pull_request: @pull, viewer: @pull.owner, repository: @source, merge_action: nil, merge_method: "squash", bypass_requirements: false)

            assert_equal @pull.owner.git_author_email, T.must(data).commit_author_email
          end
        end

        context "merge method is merge" do
          test "returns commit message body and headline" do
            data = PullRequests::PageData::MergeBox::MergeRequirementsLoader.load(pull_request: @pull, viewer: @owner, repository: @source, merge_action: nil, merge_method: "merge", bypass_requirements: false)

            refute_nil T.must(data).commit_message_body
            refute_nil T.must(data).commit_message_headline
          end

          test "returns the commit author email for the current viewer" do
            data = PullRequests::PageData::MergeBox::MergeRequirementsLoader.load(pull_request: @pull, viewer: @owner, repository: @source, merge_action: nil, merge_method: "MERGE", bypass_requirements: false)

            refute_nil T.must(data).commit_message_body
            assert_equal @owner.git_author_email, T.must(data).commit_author_email
          end

          test "returns the commit author's private email address when keep email address private is enabled" do
            @owner.primary_user_email.toggle_visibility
            refute @owner.primary_user_email.public?

            data = PullRequests::PageData::MergeBox::MergeRequirementsLoader.load(pull_request: @pull, viewer: @owner, repository: @source, merge_action: nil, merge_method: "MERGE", bypass_requirements: false)

            assert_equal @owner.git_author_email, T.must(data).commit_author_email
          end
        end
      end
    end
  end
end
