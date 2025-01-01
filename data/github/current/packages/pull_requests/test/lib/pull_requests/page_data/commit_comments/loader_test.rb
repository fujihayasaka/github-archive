# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"

module PullRequests
  module PageData
    module CommitComments
      class LoaderTest < GitHub::TestCase
        include GitHub::PullRequestTestHelpers
        include Diff
        include ConditionalAccess::FilterTestHelper

        fixtures do
          disable_feature_flag(:disable_commit_comments)
          @repository = create(:repository, from_example: :mojombo_grit)
          @user = @repository.owner


          head = @repository.commits.find("1d22e6fde59c9ded9b8093cf26213a5bd9d4c5ec")

          create(:commit_comment,
            commit_id:  head.oid,
            body:       "commit comment1",
            position:   4,
            path:       "lib/grit/commit.rb".dup,
            repository: @repository,
          )
          create(:commit_comment,
            commit_id:  head.oid,
            body:       "commit comment2",
            position:   4,
            path:       "lib/grit/commit.rb".dup,
            repository: @repository,
          )
          create(:commit_comment,
            commit_id:  head.oid,
            body:       "commit comment3",
            position:   4,
            path:       "lib/grit/commit.rb".dup,
            repository: @repository,
          )
          @cap_filter = cap_authorizing_filter.freeze
        end
        setup do
          @head = @repository.commits.find("1d22e6fde59c9ded9b8093cf26213a5bd9d4c5ec")
        end

        test "load returns an array of comments" do
          diff = GitHub::Diff.new(@repository, "40d3057d09a7a4d61059bca9dca5ae698de58cbe~",
            "40d3057d09a7a4d61059bca9dca5ae698de58cbe")
          file_list_view = FileListView.new(diffs: diff, repository: @repository)
          comments = Loader.load(
            current_user: @user,
            file_list_view: file_list_view,
            current_repository: @repository,
            cap_filter: @cap_filter
          )
          assert_instance_of Array, comments
          assert comments.all? { |comment| comment.is_a?(Loader::Comment) }
        end

        test "load_async returns a promise of comments" do
          diff = GitHub::Diff.new(@repository, "40d3057d09a7a4d61059bca9dca5ae698de58cbe~",
            "40d3057d09a7a4d61059bca9dca5ae698de58cbe")
          file_list_view = FileListView.new(diffs: diff, repository: @repository)
          promise = Loader.load_async(
            current_user: @user,
            file_list_view: file_list_view,
            current_repository: @repository,
            cap_filter: @cap_filter
          )
          assert_instance_of Promise, promise
          comments = promise.sync
          assert_instance_of Array, comments
          assert comments.all? { |comment| comment.is_a?(Loader::Comment) }
        end

        test "load with nil parameters" do
          comments = Loader.load(
            current_user: nil,
            file_list_view: nil,
            current_repository: nil,
            cap_filter: nil
          )
          assert_instance_of Array, comments
          assert comments.empty?
        end

        test "load_async with nil parameters" do
          promise = Loader.load_async(
            current_user: nil,
            file_list_view: nil,
            current_repository: nil,
            cap_filter: nil
          )
          assert_instance_of Promise, promise
          comments = promise.sync
          assert_instance_of Array, comments
          assert comments.empty?
        end

        test "comment attributes are what we expect" do
          file_list_view = FileListView.new(diffs: @head.diff, commit: @head, repository: @repository)
          comments = Loader.load(
            current_user: @user,
            file_list_view: file_list_view,
            current_repository: @repository,
            cap_filter: @cap_filter
          )

          comment = comments.first
          assert_equal "commit comment1", comment&.body
          assert_equal "<p dir=\"auto\">commit comment1</p>", comment&.html_body
          refute_nil comment&.created_at
          refute_nil comment&.updated_at
          assert_equal"lib/grit/commit.rb::4", comment&.thread_id
          assert_equal comments.length, 3
        end
      end
    end
  end
end
