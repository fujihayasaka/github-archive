# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/pull_requests"

class AllowablePullRequestMergeMethodsTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers

  fixtures do
    @user = create :user, login: "wampa", plan: "pro"
    @repo = create(:repository, owner: @user, from_example: :pull_request_source)
    @pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)
  end

  def merge_method_to_h(method)
    { name: method.name, is_allowable: method.is_allowable, is_allowable_with_bypass: method.is_allowable_with_bypass, is_default: method.is_default }
  end

  context "merge queue enabled" do
    test "it allows the merge method enabled for merge queue" do
      # :has_merge_queue defaults to allowing :merge method when used on Repository factory
      repo = create(:repository, :has_merge_queue, owner: @user)
      pr = create(:pull_request, :with_mergeable_head, repository: repo, user: @user)
      data = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: @user).sync

      expected_merge_method = {
        name: :merge,
        is_allowable: true,
        is_allowable_with_bypass: true,
        is_default: true
      }

      expected_squash_method = {
        name: :squash,
        is_allowable: false,
        is_allowable_with_bypass: false,
        is_default: false
      }

      expected_rebase_method = {
        name: :rebase,
        is_allowable: false,
        is_allowable_with_bypass: false,
        is_default: false
      }
      data.then do |resolved_data|
        assert_equal [expected_merge_method, expected_squash_method, expected_rebase_method], resolved_data.map { |action| merge_method_to_h(action) }
      end
    end
  end

  context "direct merge" do
    context "admin" do
      test "admins can bypass to merge, squash, and rebase if there are rules to bypass and all merge methods are is_allowable" do
        protected_branch = @repo.protect_branch(
          @repo.default_branch,
          creator: @repo.owner,
          entry_point: :test_case,
        )
        protected_branch.save!

        pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)

        data = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: @user).sync

        expected_merge_method = {
          name: :merge,
          is_allowable: true,
          is_allowable_with_bypass: true,
          is_default: true
        }

        expected_squash_method = {
          name: :squash,
          is_allowable: true,
          is_allowable_with_bypass: true,
          is_default: false
        }

        expected_rebase_method = {
          name: :rebase,
          is_allowable: true,
          is_allowable_with_bypass: true,
          is_default: false
        }

        data.then do |resolved_data|
          assert_equal [expected_merge_method, expected_squash_method, expected_rebase_method], resolved_data.map { |action| merge_method_to_h(action) }
        end
      end

      test "admins cannot bypass to merge if merge is not is_allowable" do
        protected_branch = @repo.protect_branch(
          @repo.default_branch,
          creator: @repo.owner,
          entry_point: :test_case,
          required_linear_history: true
        )
        protected_branch.save!

        @repo.update_merge_settings(@repo.owner,
          merge_allowed: false,
          squash_allowed: true,
          rebase_allowed: true
        )

        pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)

        data = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: @user).sync

        expected_merge_method = {
          name: :merge,
          is_allowable: false,
          is_allowable_with_bypass: false,
          is_default: false
        }

        expected_squash_method = {
          name: :squash,
          is_allowable: true,
          is_allowable_with_bypass: true,
          is_default: true
        }

        expected_rebase_method = {
          name: :rebase,
          is_allowable: true,
          is_allowable_with_bypass: true,
          is_default: false
        }

        data.then do |resolved_data|
          assert_equal [expected_merge_method, expected_squash_method, expected_rebase_method], resolved_data.map { |action| merge_method_to_h(action) }
        end
      end

      test "admins cannot bypass to squash if squash is not allowed" do
        protected_branch = @repo.protect_branch(
          @repo.default_branch,
          creator: @repo.owner,
          entry_point: :test_case,
        )
        protected_branch.save!

        @repo.update_merge_settings(@repo.owner,
          merge_allowed: true,
          squash_allowed: false,
          rebase_allowed: true
        )

        pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)

        data = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: @user).sync

        expected_merge_method = {
          name: :merge,
          is_allowable: true,
          is_allowable_with_bypass: true,
          is_default: true
        }

        expected_squash_method = {
          name: :squash,
          is_allowable: false,
          is_allowable_with_bypass: false,
          is_default: false
        }

        expected_rebase_method = {
          name: :rebase,
          is_allowable: true,
          is_allowable_with_bypass: true,
          is_default: false
        }

        data.then do |resolved_data|
          assert_equal [expected_merge_method, expected_squash_method, expected_rebase_method], resolved_data.map { |action| merge_method_to_h(action) }
        end
      end

      test "admins cannot bypass to rebase if rebase is not allowed" do
        protected_branch = @repo.protect_branch(
          @repo.default_branch,
          creator: @repo.owner,
          entry_point: :test_case,
        )
        protected_branch.save!

        @repo.update_merge_settings(@repo.owner,
          merge_allowed: true,
          squash_allowed: true,
          rebase_allowed: false
        )

        pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)

        data = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: @user).sync

        expected_merge_method = {
          name: :merge,
          is_allowable: true,
          is_allowable_with_bypass: true,
          is_default: true
        }

        expected_squash_method = {
          name: :squash,
          is_allowable: true,
          is_allowable_with_bypass: true,
          is_default: false
        }

        expected_rebase_method = {
          name: :rebase,
          is_allowable: false,
          is_allowable_with_bypass: false,
          is_default: false
        }

        data.then do |resolved_data|
          assert_equal [expected_merge_method, expected_squash_method, expected_rebase_method], resolved_data.map { |action| merge_method_to_h(action) }
        end
      end
    end

    context "non-admin" do
      test "works when there is no protected branch" do
        pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)

        non_admin = create(:user)
        @repo.add_member(non_admin)

        @repo.update_merge_settings(non_admin,
          merge_allowed: true,
          squash_allowed: false,
          rebase_allowed: false
        )

        data = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: non_admin).sync

        expected_merge_method = {
          name: :merge,
          is_allowable: true,
          is_allowable_with_bypass: false,
          is_default: true
        }

        expected_squash_method = {
          name: :squash,
          is_allowable: false,
          is_allowable_with_bypass: false,
          is_default: false
        }

        expected_rebase_method = {
          name: :rebase,
          is_allowable: false,
          is_allowable_with_bypass: false,
          is_default: false
        }

        data.then do |resolved_data|
          assert_equal [expected_merge_method, expected_squash_method, expected_rebase_method], resolved_data.map { |action| merge_method_to_h(action) }
        end
      end

      test "can merge if that method is accessible to them, they cannot squash or rebase" do
        protected_branch = @repo.protect_branch(
          @repo.default_branch,
          creator: @repo.owner,
          entry_point: :test_case,
        )
        protected_branch.save!

        pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)

        non_admin = create(:user)
        @repo.add_member(non_admin)

        @repo.update_merge_settings(non_admin,
          merge_allowed: true,
          squash_allowed: false,
          rebase_allowed: false
        )

        data = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: non_admin).sync

        expected_merge_method = {
          name: :merge,
          is_allowable: true,
          is_allowable_with_bypass: false,
          is_default: true
        }

        expected_squash_method = {
          name: :squash,
          is_allowable: false,
          is_allowable_with_bypass: false,
          is_default: false
        }

        expected_rebase_method = {
          name: :rebase,
          is_allowable: false,
          is_allowable_with_bypass: false,
          is_default: false
        }

        data.then do |resolved_data|
          assert_equal [expected_merge_method, expected_squash_method, expected_rebase_method], resolved_data.map { |action| merge_method_to_h(action) }
        end
      end

      test "can squash merge if that method accessible to them, they cannot merge commit or rebase" do
        protected_branch = @repo.protect_branch(
          @repo.default_branch,
          creator: @repo.owner,
          entry_point: :test_case,
        )
        protected_branch.save!

        @repo.update_merge_settings(@repo.owner,
          merge_allowed: false,
          squash_allowed: true,
          rebase_allowed: false
        )
        pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)

        non_admin = create(:user)
        @repo.add_member(non_admin)

        data = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: non_admin).sync

        expected_merge_method = {
          name: :merge,
          is_allowable: false,
          is_allowable_with_bypass: false,
          is_default: false
        }

        expected_squash_method = {
          name: :squash,
          is_allowable: true,
          is_allowable_with_bypass: false,
          is_default: true
        }

        expected_rebase_method = {
          name: :rebase,
          is_allowable: false,
          is_allowable_with_bypass: false,
          is_default: false
        }

        data.then do |resolved_data|
          assert_equal [expected_merge_method, expected_squash_method, expected_rebase_method], resolved_data.map { |action| merge_method_to_h(action) }
        end
      end

      test "can rebase merge if that method accessible to them, they cannot merge commit or squash" do
        protected_branch = @repo.protect_branch(
          @repo.default_branch,
          creator: @repo.owner,
          entry_point: :test_case,
        )
        protected_branch.save!

        @repo.update_merge_settings(@repo.owner,
          merge_allowed: false,
          squash_allowed: false,
          rebase_allowed: true
        )

        pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)

        non_admin = create(:user)
        @repo.add_member(non_admin)

        data = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: non_admin).sync

        expected_merge_method = {
          name: :merge,
          is_allowable: false,
          is_allowable_with_bypass: false,
          is_default: false
        }

        expected_squash_method = {
          name: :squash,
          is_allowable: false,
          is_allowable_with_bypass: false,
          is_default: false
        }

        expected_rebase_method = {
          name: :rebase,
          is_allowable: true,
          is_allowable_with_bypass: false,
          is_default: true
        }

        data.then do |resolved_data|
          assert_equal [expected_merge_method, expected_squash_method, expected_rebase_method], resolved_data.map { |action| merge_method_to_h(action) }
        end
      end

      test "can squash or rebase, but cannot merge commit when linear branch protection is enabled" do
        protected_branch = @repo.protect_branch(
          @repo.default_branch,
          creator: @repo.owner,
          entry_point: :test_case,
          required_linear_history: true
        )
        protected_branch.save!

        @repo.update_merge_settings(@repo.owner,
          merge_allowed: false,
          squash_allowed: true,
          rebase_allowed: true
        )

        pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)

        non_admin = create(:user)
        @repo.add_member(non_admin)

        data = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: non_admin).sync

        expected_merge_method = {
          name: :merge,
          is_allowable: false,
          is_allowable_with_bypass: false,
          is_default: false
        }

        expected_squash_method = {
          name: :squash,
          is_allowable: true,
          is_allowable_with_bypass: false,
          is_default: true
        }

        expected_rebase_method = {
          name: :rebase,
          is_allowable: true,
          is_allowable_with_bypass: false,
          is_default: false
        }

        data.then do |resolved_data|
          assert_equal [expected_merge_method, expected_squash_method, expected_rebase_method], resolved_data.map { |action| merge_method_to_h(action) }
        end
      end

      test "merge commit is not default method when linear branch protection is enabled" do
        protected_branch = @repo.protect_branch(
          @repo.default_branch,
          creator: @repo.owner,
          entry_point: :test_case,
          required_linear_history: true
        )
        protected_branch.save!

        @repo.update_merge_settings(@repo.owner,
          merge_allowed: true,
          squash_allowed: true,
          rebase_allowed: true
        )

        pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)

        non_admin = create(:user)
        @repo.add_member(non_admin)

        data = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: non_admin).sync

        expected_merge_method = {
          name: :merge,
          is_allowable: false,
          is_allowable_with_bypass: false,
          is_default: false
        }

        expected_squash_method = {
          name: :squash,
          is_allowable: true,
          is_allowable_with_bypass: false,
          is_default: true
        }

        expected_rebase_method = {
          name: :rebase,
          is_allowable: true,
          is_allowable_with_bypass: false,
          is_default: false
        }

        data.then do |resolved_data|
          assert_equal [expected_merge_method, expected_squash_method, expected_rebase_method], resolved_data.map { |action| merge_method_to_h(action) }
        end
      end
    end

    test "returns default: true for the viewer's last used merge method" do
      protected_branch = @repo.protect_branch(
        @repo.default_branch,
        creator: @repo.owner,
        entry_point: :test_case,
      )
      protected_branch.save!

      pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)

      non_admin = create(:user)
      @repo.add_member(non_admin)

      default_merge_method = @repo.default_merge_method_for(@user)

      data = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: @user).sync

      data.then do |resolved_data|
        if resolved_data.nil?
          puts "No resolved data."
        else
          default_action = resolved_data.find { |action| action.is_default }
          assert_equal default_merge_method, default_action&.name
        end
      end
    end
  end
end
