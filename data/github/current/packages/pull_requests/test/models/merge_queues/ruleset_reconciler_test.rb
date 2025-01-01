# typed: true
# frozen_string_literal: true

require "test_helper"

module MergeQueues
  class RulesetReconcilerTest < GitHub::TestCase
    fixtures do
      @user = create(:user)
      @org = create(:organization, admin: @user, plan: "business_plus")
      @repository = create(:repository, owner: @org)
    end

    context "#reconcile_all" do
      test "creates a missing merge queue" do
        create_merge_queue_ruleset(branches: ["refs/heads/main"])

        RulesetReconciler.new(@repository).reconcile_all

        assert_equal 1, MergeQueue.count
        queue = T.must(MergeQueue.first)
        assert_equal @repository.id, queue.repository_id
        assert_equal "main", queue.branch
        assert_nil queue.protected_branch_id
      end

      test "creates a merge queue for the default branch" do
        create_merge_queue_ruleset(branches: ["~DEFAULT_BRANCH"])

        RulesetReconciler.new(@repository).reconcile_all

        assert_equal 1, MergeQueue.count
        queue = T.must(MergeQueue.first)
        assert_equal @repository.id, queue.repository_id
        assert_equal @repository.default_branch, queue.branch
        assert_nil queue.protected_branch_id
      end

      test "destroys a redundant merge queue" do
        create(:merge_queue, repository: @repository, branch: "test", protected_branch: nil)

        RulesetReconciler.new(@repository).reconcile_all

        assert_equal 0, MergeQueue.count
      end

      test "only creates queues for enabled rulesets" do
        enforcement_levels = RepositoryRuleset.enforcements.keys
        assert(
          enforcement_levels.include?("enabled"),
          "Invalid test assumption: 'enabled' is no longer a valid "\
          "RepositoryRuleset enforcement level, this test needs to be updated.",
        )

        enforcement_levels.each do |enforcement_level|
          create_merge_queue_ruleset(
            branches: ["refs/heads/#{enforcement_level}-branch"],
            enforcement: enforcement_level.to_sym,
          )
        end

        RulesetReconciler.new(@repository).reconcile_all

        assert_same_elements ["enabled-branch"], MergeQueue.pluck(:branch)
      end

      test "does not re-create existing queues" do
        create_merge_queue_ruleset(branches: ["refs/heads/main"])
        existing_queue = create_merge_queue(branch: "main")

        RulesetReconciler.new(@repository).reconcile_all

        assert_equal 1, MergeQueue.count
        found_queue = MergeQueue.first
        assert_equal existing_queue.id, T.must(found_queue).id
      end

      test "performs multiple operations in a single call" do
        create_merge_queue_ruleset(
          branches: ["refs/heads/main", "refs/heads/integration", "refs/heads/production"]
        )
        create_merge_queue(branch: "redundant")
        create_merge_queue(branch: "production")

        RulesetReconciler.new(@repository.reload).reconcile_all

        assert_equal 3, MergeQueue.count
        assert_same_elements %w[main integration production], MergeQueue.pluck(:branch)
      end

      test "does not destroy a legacy merge queue associated with a protected branch" do
        protected_branch = @repository.protect_branch("main", creator: @user)
        legacy_queue = create_merge_queue(branch: "main", protected_branch:)

        RulesetReconciler.new(@repository).reconcile_all

        assert_equal 1, MergeQueue.count
        assert_equal legacy_queue, MergeQueue.first
      end
    end

    context "#reconcile_default_branch_rename" do
      test "updates an existing queue for the default branch when there is a ~DEFAULT_BRANCH rule" do
        create_merge_queue_ruleset(branches: ["~DEFAULT_BRANCH"])
        existing_queue = create_merge_queue(branch: "trunk")

        RulesetReconciler.new(@repository.reload).reconcile_default_branch_rename(
          old_name: "trunk",
          new_name: "main",
        )

        assert_equal 1, MergeQueue.count
        found_queue = T.must(MergeQueue.first)
        assert_equal existing_queue.id, found_queue.id
        assert_equal "main", found_queue.branch
      end

      test "does not update an existing queue for the default branch when there is not a ~DEFAULT_BRANCH rule" do
        create_merge_queue_ruleset(branches: ["refs/heads/trunk"])
        existing_queue = create_merge_queue(branch: "trunk")

        RulesetReconciler.new(@repository.reload).reconcile_default_branch_rename(
          old_name: "trunk",
          new_name: "main",
        )

        assert_equal 1, MergeQueue.count
        found_queue = MergeQueue.first
        assert_equal existing_queue.id, T.must(found_queue).id
        assert_equal "trunk", T.must(found_queue).branch
      end

      test "creates a new queue for the old default branch name if explicitly targeted" do
        create_merge_queue_ruleset(branches: ["refs/heads/trunk", "~DEFAULT_BRANCH"])
        existing_queue = create_merge_queue(branch: "trunk")

        RulesetReconciler.new(@repository.reload).reconcile_default_branch_rename(
          old_name: "trunk",
          new_name: "main",
        )

        assert_equal 2, MergeQueue.count
        assert_same_elements %w[main trunk], MergeQueue.pluck(:branch)
        assert_equal "main", existing_queue.reload.branch
      end
    end

    private

    sig { params(branches: T::Array[String], enforcement: Symbol).returns(RepositoryRuleset) }
    def create_merge_queue_ruleset(branches:, enforcement: :enabled)
      # Stub the reconciler, so that creating the RepositoryRuleset record
      # doesn't trigger it via a callback.
      stub_reconciler do
        create(
          :repository_ruleset,
          source: @repository,
          enforcement:,
          rule_configurations: [
            build(:repository_rule_configuration, :merge_queue),
          ],
          conditions: [
            build(
              :repository_rule_condition,
              target: "ref_name",
              parameters: {
                include: branches,
                exclude: [],
              },
            )
          ],
        )
      end
    end

    sig { params(branch: String, protected_branch: T.nilable(ProtectedBranch)).returns(MergeQueue) }
    def create_merge_queue(branch:, protected_branch: nil)
      create(:merge_queue, repository: @repository, branch:, protected_branch:)
    end

    sig do
      type_parameters(:Result)
        .params(block: T.proc.returns(T.type_parameter(:Result)))
        .returns(T.type_parameter(:Result))
    end
    def stub_reconciler(&block)
      RulesetReconciler.any_instance.stubs(:reconcile_all)
      yield
    ensure
      RulesetReconciler.any_instance.unstub(:reconcile_all)
    end
  end
end
