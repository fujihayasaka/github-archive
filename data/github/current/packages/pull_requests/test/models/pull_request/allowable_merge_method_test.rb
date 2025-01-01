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

  sig { params(method: PullRequest::AllowableMergeMethod).returns(T::Hash[Symbol, T.untyped]) }
  def merge_method_to_h(method)
    { name: method.name, allowable_status: method.allowable_status, is_default: method.is_default }
  end

  context "merge queue enabled" do
    test "it allows the merge method enabled for merge queue" do
      # :has_merge_queue defaults to allowing :merge method when used on Repository factory
      repo = create(:repository, :has_merge_queue, owner: @user)
      pr = create(:pull_request, :with_mergeable_head, repository: repo, user: @user)
      data = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: @user).sync

      expected_merge_method = {
        name: :merge,
        allowable_status: :allowed,
        is_default: true
      }

      expected_squash_method = {
        name: :squash,
        allowable_status: :blocked,
        is_default: false
      }

      expected_rebase_method = {
        name: :rebase,
        allowable_status: :blocked,
        is_default: false
      }
      data.then do |resolved_data|
        assert_equal [expected_merge_method, expected_squash_method, expected_rebase_method], resolved_data.map { |action| merge_method_to_h(action) }
      end
    end
  end

  context "direct merge" do
    context "admin" do
      test "admins can bypass to merge, squash, and rebase if there are rules to bypass and all merge methods are allowed" do
        protected_branch = @repo.protect_branch(
          @repo.default_branch,
          creator: @repo.owner,
          entry_point: :test_case,
        )
        protected_branch.save!

        pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)
        PullRequest::MergeState.any_instance.stubs(:admin_override_possible?).returns(true)

        data = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: @user).sync

        expected_merge_method = {
          name: :merge,
          allowable_status: :allowed,
          is_default: true
        }

        expected_squash_method = {
          name: :squash,
          allowable_status: :allowed,
          is_default: false
        }

        expected_rebase_method = {
          name: :rebase,
          allowable_status: :allowed,
          is_default: false
        }

        data.then do |resolved_data|
          assert_equal [expected_merge_method, expected_squash_method, expected_rebase_method], resolved_data.map { |action| merge_method_to_h(action) }
        end
      end

      test "admins cannot bypass to merge if merge is blocked" do
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
          allowable_status: :blocked,
          is_default: false
        }

        expected_squash_method = {
          name: :squash,
          allowable_status: :allowed,
          is_default: true
        }

        expected_rebase_method = {
          name: :rebase,
          allowable_status: :allowed,
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
        PullRequest::MergeState.any_instance.stubs(:admin_override_possible?).returns(true)

        data = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: @user).sync

        expected_merge_method = {
          name: :merge,
          allowable_status: :allowed,
          is_default: true
        }

        expected_squash_method = {
          name: :squash,
          allowable_status: :blocked,
          is_default: false
        }

        expected_rebase_method = {
          name: :rebase,
          allowable_status: :allowed,
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
        PullRequest::MergeState.any_instance.stubs(:admin_override_possible?).returns(true)

        data = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: @user).sync

        expected_merge_method = {
          name: :merge,
          allowable_status: :allowed,
          is_default: true
        }

        expected_squash_method = {
          name: :squash,
          allowable_status: :allowed,
          is_default: false
        }

        expected_rebase_method = {
          name: :rebase,
          allowable_status: :blocked,
          is_default: false
        }

        data.then do |resolved_data|
          assert_equal [expected_merge_method, expected_squash_method, expected_rebase_method], resolved_data.map { |action| merge_method_to_h(action) }
        end
      end
    end

    context "non-admin" do
      test "works when there is no protected branch" do
        non_admin = create(:user)
        @repo.add_member(non_admin)

        @repo.update_merge_settings(non_admin,
          merge_allowed: true,
          squash_allowed: false,
          rebase_allowed: false
        )

        pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)

        data = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: non_admin).sync

        expected_merge_method = {
          name: :merge,
          allowable_status: :allowed,
          is_default: true
        }

        expected_squash_method = {
          name: :squash,
          allowable_status: :blocked,
          is_default: false
        }

        expected_rebase_method = {
          name: :rebase,
          allowable_status: :blocked,
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

        non_admin = create(:user)
        @repo.add_member(non_admin)

        @repo.update_merge_settings(non_admin,
          merge_allowed: true,
          squash_allowed: false,
          rebase_allowed: false
        )

        pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)

        data = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: non_admin).sync

        expected_merge_method = {
          name: :merge,
          allowable_status: :allowed,
          is_default: true
        }

        expected_squash_method = {
          name: :squash,
          allowable_status: :blocked,
          is_default: false
        }

        expected_rebase_method = {
          name: :rebase,
          allowable_status: :blocked,
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
          allowable_status: :blocked,
          is_default: false
        }

        expected_squash_method = {
          name: :squash,
          allowable_status: :allowed,
          is_default: true
        }

        expected_rebase_method = {
          name: :rebase,
          allowable_status: :blocked,
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
          allowable_status: :blocked,
          is_default: false
        }

        expected_squash_method = {
          name: :squash,
          allowable_status: :blocked,
          is_default: false
        }

        expected_rebase_method = {
          name: :rebase,
          allowable_status: :allowed,
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
          allowable_status: :blocked,
          is_default: false
        }

        expected_squash_method = {
          name: :squash,
          allowable_status: :allowed,
          is_default: true
        }

        expected_rebase_method = {
          name: :rebase,
          allowable_status: :allowed,
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
          allowable_status: :blocked,
          is_default: false
        }

        expected_squash_method = {
          name: :squash,
          allowable_status: :allowed,
          is_default: true
        }

        expected_rebase_method = {
          name: :rebase,
          allowable_status: :allowed,
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

    context "interactions with rulesets" do
      test "linear history rule present but disabled" do
        no_bypass_ruleset = create(
          :repository_ruleset,
          :targets_default_branch,
          enforcement: :disabled,
          source: @repo,
        )
        create(
          :repository_rule_configuration,
          rule_type: "required_linear_history",
          repository_ruleset: no_bypass_ruleset,
        )

        # All methods are available unless ruleset is blocking
        @repo.update_merge_settings(@repo.owner, merge_allowed: true, squash_allowed: true, rebase_allowed: true)

        pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)

        non_admin = create(:user)
        @repo.add_member(non_admin)

        expected = [
          { name: :merge, allowable_status: :allowed, is_default: true },
          { name: :squash, allowable_status: :allowed, is_default: false },
          { name: :rebase, allowable_status: :allowed, is_default: false },
        ]

        # Non-admin can merge, squash or rebase. Default: merge.
        actual = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: non_admin).sync
        assert_equal(expected, actual.map { |method| merge_method_to_h(method) })

        # Repo admin can merge, squash or rebase. Default: merge.
        actual = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: @user).sync
        assert_equal(expected, actual.map { |method| merge_method_to_h(method) })
      end

      test "linear history rule enabled with no bypass" do
        no_bypass_ruleset = create(
          :repository_ruleset,
          :targets_default_branch,
          enforcement: :enabled,
          source: @repo,
        )
        create(
          :repository_rule_configuration,
          rule_type: "required_linear_history",
          repository_ruleset: no_bypass_ruleset,
        )

        # All methods are available unless ruleset is blocking
        @repo.update_merge_settings(@repo.owner, merge_allowed: true, squash_allowed: true, rebase_allowed: true)

        pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)

        non_admin = create(:user)
        @repo.add_member(non_admin)

        expected = [
          { name: :merge,  allowable_status: :blocked, is_default: false },
          { name: :squash, allowable_status: :allowed, is_default: true },
          { name: :rebase, allowable_status: :allowed, is_default: false },
        ]

        # Non-admin can squash or rebase. Default: squash.
        actual = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: non_admin).sync
        assert_equal(expected, actual.map { |method| merge_method_to_h(method) })

        # Repo admin can squash or rebase. Default: squash.
        actual = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: @user).sync
        assert_equal(expected, actual.map { |method| merge_method_to_h(method) })
      end

      test "linear history rule enabled with 'PR-only' bypass for repo admins" do
        # Disabled ruleset with required linear history, repo admins can bypass via PR
        admin_bypass_via_pr_ruleset = create(
          :repository_ruleset,
          :targets_default_branch,
          enforcement: :enabled,
          source: @repo
        )
        create(
          :repository_rule_configuration,
          rule_type: "required_linear_history",
          repository_ruleset: admin_bypass_via_pr_ruleset,
        )
        create(:repository_ruleset_bypass_actor, :repo_admin,
          bypass_mode: RepositoryRulesetBypassActor::BYPASS_MODES[:pull_request],
          repository_ruleset: admin_bypass_via_pr_ruleset
        )

        # All methods are available unless ruleset is blocking
        @repo.update_merge_settings(@repo.owner, merge_allowed: true, squash_allowed: true, rebase_allowed: true)

        pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)

        non_admin = create(:user)
        @repo.add_member(non_admin)

        # Non-admin can squash or rebase. Default: squash.
        expected = [
          { name: :merge,  allowable_status: :blocked, is_default: false },
          { name: :squash, allowable_status: :allowed, is_default: true },
          { name: :rebase, allowable_status: :allowed, is_default: false },
        ]
        actual = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: non_admin).sync
        assert_equal(expected, actual.map { |method| merge_method_to_h(method) })

        # Repo admin can squash, rebase, or merge via bypass since a PR is being used.
        # Default: squash (bypassing rules should never be the default action).
        expected = [
          { name: :merge,  allowable_status: :allowed_with_bypass, is_default: false },
          { name: :squash, allowable_status: :allowed,             is_default: true },
          { name: :rebase, allowable_status: :allowed,             is_default: false },
        ]
        actual = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: @user).sync
        assert_equal(expected, actual.map { |method| merge_method_to_h(method) })
      end

      test "pull_request rule blocking :merge" do
        ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo)
        create(:repository_rule_configuration, :pull_request, allowed_merge_methods: %w[squash rebase], repository_ruleset: ruleset)

        # All methods are available unless ruleset is blocking
        @repo.update_merge_settings(@repo.owner, merge_allowed: true, squash_allowed: true, rebase_allowed: true)

        pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)

        expected = [
          { name: :merge,  allowable_status: :blocked, is_default: false },
          { name: :squash, allowable_status: :allowed, is_default: true },
          { name: :rebase, allowable_status: :allowed, is_default: false },
        ]

        actual = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: @user).sync
        assert_equal(expected, actual.map { |method| merge_method_to_h(method) })
      end

      test "pull_request rule blocking :merge and :squash" do
        ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo)
        create(:repository_rule_configuration, :pull_request, allowed_merge_methods: %w[rebase], repository_ruleset: ruleset)

        # All methods are available unless ruleset is blocking
        @repo.update_merge_settings(@repo.owner, merge_allowed: true, squash_allowed: true, rebase_allowed: true)

        pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)

        non_admin = create(:user)
        @repo.add_member(non_admin)

        expected = [
          { name: :merge,  allowable_status: :blocked, is_default: false },
          { name: :squash, allowable_status: :blocked, is_default: false },
          { name: :rebase, allowable_status: :allowed, is_default: true },
        ]

        # Non-admin can rebase. Default: rebase.
        actual = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: non_admin).sync
        assert_equal(expected, actual.map { |method| merge_method_to_h(method) })

        # Repo admin can rebase. Default: rebase.
        actual = PullRequest::AllowableMergeMethod.for(pull_request: pr, viewer: @user).sync
        assert_equal(expected, actual.map { |method| merge_method_to_h(method) })
      end
    end
  end
end
