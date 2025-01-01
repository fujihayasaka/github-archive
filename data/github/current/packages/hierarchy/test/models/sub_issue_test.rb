# typed: true
# frozen_string_literal: true
require "test_helper"

class SubIssueTest < GitHub::TestCase
  include PrioritizationHelpers
  include HydroTestHelpers
  include SubIssuesHelpers
  include DogstatsTestHelpers
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @org = create(:organization)
    @repo = create(:repository, owner: @org)
    @parent = create(:issue, title: "parent", repository: @repo)
    @child1 = create(:issue, title: "child 1", repository: @repo)
    @child2 = create(:issue, title: "child 2", repository: @repo)
    @child3 = create(:issue, title: "child 3", repository: @repo)
    @user = create(:user)
    @org.add_member(@user)
    @pull = create(:pull_request, :disable_disk_access, repository: @repo)
  end

  test "requires an actor" do
    refute_predicate build(:sub_issue, actor: nil), :valid?
    assert_predicate build(:sub_issue, actor: @user), :valid?
  end

  context "add_sub_issue!" do
    test "should be able to add sub-issues" do
      @parent.add_sub_issue!(@child1, @user.id)

      assert_equal @child1, @parent.sub_issues.first
      assert_equal @parent, @child1.parent
    end

    test "should be able to remove sub-issues" do
      rel1 = @parent.add_sub_issue!(@child1, @user.id)

      assert_equal @child1, @parent.sub_issues.first
      assert_equal @parent, @child1.parent

      rel1.destroy

      assert_empty @parent.sub_issues
      assert_nil @child1.reload.parent
    end
  end

  context "prioritize_dependent!" do
    test "should be able to reorder sub-issues" do
      allow_transaction_nesting do
        rel1 = @parent.add_sub_issue!(@child1, @user.id)
        rel2 = @parent.add_sub_issue!(@child2, @user.id)
        rel3 = @parent.add_sub_issue!(@child3, @user.id)

        assert_equal [@child1, @child2, @child3], @parent.prioritized_sub_issues

        # move 1 after 2
        @parent.prioritize_dependent!(rel1, after: rel2)
        # move 3 to the beginning
        @parent.prioritize_dependent!(rel3, position: :top)

        @parent.reload

        assert_equal [@child3, @child2, @child1], @parent.prioritized_sub_issues
      end
    end
  end

  context "add_sub_issue!" do
    test "should be able to remove a sub-issue" do
      @parent.add_sub_issue!(@child1, @user.id)
      @parent.add_sub_issue!(@child2, @user.id)

      assert_equal [@child1, @child2], @parent.prioritized_sub_issues

      @parent.remove_sub_issue!(@child1)
      @parent.reload

      assert_equal [@child2], @parent.prioritized_sub_issues
    end
  end

  context "pull requests" do
    test "does not allow for issues with pull requests to be added as sub_issues" do
      relationship = @parent.add_sub_issue!(@pull.issue, @user.id)
      refute relationship.persisted?

      assert_includes("Sub issue may only be an issue", relationship.errors.full_messages.to_sentence)
    end

    test "does not allow for issues with pull requests to be added as parents" do
      relationship = @pull.issue.add_sub_issue!(@child1, @user.id)
      refute relationship.persisted?

      assert_includes("Parent may only be an issue", relationship.errors.full_messages.to_sentence)
    end
  end

  context "only_one_parent" do
    test "does not allow for an issue to be added as a sub-issue to multiple parents" do
      create_hierarchy!("
      - #{@parent}
        - #{@child1}
      ", issues: [@parent, @child1])

      assert_raises(StandardError, "Failed to add sub-issue: may only have one parent") do
        @child1.parent = [@child2]
        @child1.save!
      end
    end
  end

  context "limits: breadth" do
    test "does allow fewer than the limit of sub-issues per parent" do
      @parent.add_sub_issue!(@child1, @user.id)

      SubIssue.stub_const(:MAXIMUM_BREADTH, 3) do
        assert @parent.add_sub_issue!(@child2, @user.id)
      end
    end

    test "does not allow more than the limit of sub-issues parent" do
      create_hierarchy!("
      - #{@parent}
        - #{@child1}
        - #{@child2}
      ", issues: [@parent, @child1, @child2])

      SubIssue.stub_const(:MAXIMUM_BREADTH, 1) do
        relationship = @parent.add_sub_issue!(@child3, @user.id)
        refute relationship.persisted?

        assert_includes("Parent cannot have more than 1 sub-issues", relationship.errors.full_messages.to_sentence)
      end
      assert_equal 1, GitHub.dogstats.increments("sub_issue.maximum_breadth_hit").length
    end
  end

  test "instruments addition for hydro" do
    Timecop.freeze do
      repo = create(:repository)
      parent = create(:issue, repository: repo)
      child1 = create(:issue, title: "child 1", repository: repo)

      parent.add_sub_issue!(child1, @user.id)

      assert_hydro_messages(count: 1, schema: "github.v1.SubIssueAdd")
      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@user),
        source_issue_repository: Hydro::EntitySerializer.repository(parent.repository),
        source_issue: Hydro::EntitySerializer.issue(parent),
        target_issue: Hydro::EntitySerializer.issue(child1),
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        transfer: false,
      }, schema: "github.v1.SubIssueAdd")
    end
  end

  test "instruments removal for hydro" do
    Timecop.freeze do
      repo = create(:repository)
      parent = create(:issue, repository: repo)
      child1 = create(:issue, title: "child 1", repository: repo)
      destroyer = create(:user)

      parent.add_sub_issue!(child1, @user.id)
      GitHub.context.push(actor_id: destroyer.id)
      parent.remove_sub_issue!(child1)

      assert_hydro_messages(count: 1, schema: "github.v1.SubIssueRemove")
      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(destroyer),
        source_issue_repository: Hydro::EntitySerializer.repository(parent.repository),
        source_issue: Hydro::EntitySerializer.issue(parent),
        target_issue: Hydro::EntitySerializer.issue(child1),
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      }, schema: "github.v1.SubIssueRemove")
    end
  end

  context "instrument_transfer_and_notify" do
    test "instruments transfer for hydro" do
      Timecop.freeze do
        repo = create(:repository)
        parent = create(:issue, repository: repo)
        child1 = create(:issue, title: "child 1", repository: repo)

        parent.add_sub_issue!(child1, @user.id)
        reset_hydro

        child1.parent_issue_relation.instrument_transfer_and_notify(@user)
        assert_hydro_messages(count: 1, schema: "github.v1.SubIssueAdd")
        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(@user),
          source_issue_repository: Hydro::EntitySerializer.repository(parent.repository),
          source_issue: Hydro::EntitySerializer.issue(parent),
          target_issue: Hydro::EntitySerializer.issue(child1),
          existing: true,
          transfer: true,
        }, schema: "github.v1.SubIssueAdd")
      end
    end

    test "notifies related issues" do
      frozen_now = Time.utc(2024, 7, 16, 21, 16, 9).freeze
      repo = create(:repository)
      parent = create(:issue, repository: repo)
      child1 = create(:issue, title: "child 1", repository: repo)
      parent.add_sub_issue!(child1, @user.id)

      Timecop.freeze frozen_now do
        GitHub::WebSocket.stubs(:notify_graphql_subscription_channel)
        GitHub::WebSocket.expects(:notify_graphql_subscription_channel).with(any_parameters)

        parent_topic = ":issueUpdated:id:#{parent.global_relay_id}"
        parent_channel_name = Platform::Subscription.current_format.generate_channel_name(
          topic: parent_topic,
          subscription_arguments: { id: parent.global_relay_id }
        )
        GitHub::WebSocket.expects(:notify_graphql_subscription_channel).with(parent_channel_name, {
          scope_object: {
            sub_issues_updated: true
          },
          subscription_topic: parent_topic,
          scope: nil,
          dispatch_time: frozen_now.to_f,
        })

        child_topic = ":issueUpdated:id:#{child1.global_relay_id}"
        child_channel_name = Platform::Subscription.current_format.generate_channel_name(
          topic: child_topic,
          subscription_arguments: { id: child1.global_relay_id }
        )
        GitHub::WebSocket.expects(:notify_graphql_subscription_channel).with(child_channel_name, {
          scope_object: {
            parent_issue_updated: true
          },
          subscription_topic: child_topic,
          scope: nil,
          dispatch_time: frozen_now.to_f,
        })
        child1.parent_issue_relation.instrument_transfer_and_notify(@user)
      end
    end

    test "optionally skips notifying parent for sub-issue changes" do
      frozen_now = Time.utc(2024, 7, 16, 21, 16, 9).freeze
      repo = create(:repository)
      parent = create(:issue, repository: repo)
      child1 = create(:issue, title: "child 1", repository: repo)
      parent.add_sub_issue!(child1, @user.id)

      Timecop.freeze frozen_now do
        GitHub::WebSocket.stubs(:notify_graphql_subscription_channel)
        GitHub::WebSocket.expects(:notify_graphql_subscription_channel).with(any_parameters)

        parent_topic = ":issueUpdated:id:#{parent.global_relay_id}"
        parent_channel_name = Platform::Subscription.current_format.generate_channel_name(
          topic: parent_topic,
          subscription_arguments: { id: parent.global_relay_id }
        )
        GitHub::WebSocket.expects(:notify_graphql_subscription_channel).never.with(parent_channel_name, {
          scope_object: {
            sub_issues_updated: true
          },
          subscription_topic: parent_topic,
          scope: nil,
          dispatch_time: frozen_now.to_f,
        })

        child_topic = ":issueUpdated:id:#{child1.global_relay_id}"
        child_channel_name = Platform::Subscription.current_format.generate_channel_name(
          topic: child_topic,
          subscription_arguments: { id: child1.global_relay_id }
        )
        GitHub::WebSocket.expects(:notify_graphql_subscription_channel).with(child_channel_name, {
          scope_object: {
            parent_issue_updated: true
          },
          subscription_topic: child_topic,
          scope: nil,
          dispatch_time: frozen_now.to_f,
        })
        child1.parent_issue_relation.instrument_transfer_and_notify(@user, true)
      end
    end
  end

  test "self-association: does not allow a sub-issue to be its own parent" do
    relationship = @child1.add_sub_issue!(@child1, @user.id)
    refute relationship.persisted?

    assert_includes("Sub issue cannot be the same as the parent issue", relationship.errors.full_messages.to_sentence)
  end

  context "must have the same owner" do
    test "works with the same owner" do
      assert @parent.add_sub_issue!(@child1, @user.id)
    end

    test "is invalid with different owners" do
      other_owner = create(:issue)
      refute_equal @parent.repository.owner_id, other_owner.repository.owner_id

      relationship = @parent.add_sub_issue!(other_owner, @user.id)
      refute relationship.persisted?

      assert_includes("Sub issue must have the same owner as the parent", relationship.errors.full_messages.to_sentence)
      assert_equal 1, GitHub.dogstats.increments("sub_issue.different_owners_attempted").length
    end
  end

  context "source_issue_authorizable" do
    test "returns authorizable for sub-issue" do
      relation = @parent.add_sub_issue!(@child1, @user.id)
      assert_equal @parent.to_issue_authorizable.issue_id, relation.source_issue_authorizable.issue_id
      assert_equal @parent.to_issue_authorizable.repository_id, relation.source_issue_authorizable.repository_id
    end
  end

  test "doesn't allow the creation of circular references in hierarchy" do
    @parent.add_sub_issue!(@child1, @user.id)
    @child1.add_sub_issue!(@child2, @user.id)
    @child2.add_sub_issue!(@child3, @user.id)

    relationship = @child3.add_sub_issue!(@parent, @user.id)
    refute relationship.persisted?

    assert_includes("Sub issue may not create a circular dependency.", relationship.errors.full_messages.to_sentence)

    assert_equal 1, GitHub.dogstats.increments("sub_issue.circular_reference_attempted").length
  end

  context "issue transfers" do
    test "doesn't allow adding sub-issues to a parent that is being transferred to a new issue" do
      new_repository = create(:repository, owner: @org)
      @repo.add_member(@user, action: :write)
      new_repository.add_member(@user, action: :write)

      transfer = IssueTransfer.new(old_issue: @parent, old_repository: @repo, new_repository:, actor: @user)
      transfer.send(:create_copy_issue)

      transferred_parent = T.must(transfer.new_issue)

      relationship = transferred_parent.add_sub_issue!(@child1, @user.id)
      refute relationship.persisted?

      assert_includes("Source cannot create sub-issues while a transfer is in-progress", relationship.errors.full_messages.to_sentence)
      assert_equal 1, GitHub.dogstats.increments("sub_issue.create_during_transfer_attempted").length
    end

    test "doesn't allow adding sub-issues to a parent that is being transferred from an old issue" do
      new_repository = create(:repository, owner: @org)
      @repo.add_member(@user, action: :write)
      new_repository.add_member(@user, action: :write)

      transfer = IssueTransfer.new(old_issue: @parent, old_repository: @repo, new_repository:, actor: @user)
      transfer.send(:create_copy_issue)

      relationship = @parent.add_sub_issue!(@child1, @user.id)
      refute relationship.persisted?

      assert_includes("Source cannot create sub-issues while a transfer is in-progress", relationship.errors.full_messages.to_sentence)
      assert_equal 1, GitHub.dogstats.increments("sub_issue.create_during_transfer_attempted").length
    end

    test "doesn't allow updating sub-issues on a parent that is being transferred to a new issue" do
      new_repository = create(:repository, owner: @org)
      @repo.add_member(@user, action: :write)
      new_repository.add_member(@user, action: :write)

      transfer = IssueTransfer.new(old_issue: @parent, old_repository: @repo, new_repository:, actor: @user)
      transfer.send(:create_copy_issue)

      transferred_parent = T.must(transfer.new_issue)

      SubIssue.build(
        source_issue_id: transferred_parent.id,
        source_repository_id: transferred_parent.repository_id,
        target_issue_id: @child1.id,
        actor_id: @user.id,
        priority: 1
      ).save(validate: false)

      assert_raises(StandardError, "Failed to add sub-issue: Source cannot update sub-issues while a transfer is in-progress") do
        transferred_parent.sub_issue_relations.first.update!(priority: 2)
      end
      assert_equal 1, GitHub.dogstats.increments("sub_issue.update_during_transfer_attempted").length
    end

    test "doesn't allow updating sub-issues on a parent that is being transferred from an old issue" do
      new_repository = create(:repository, owner: @org)
      @repo.add_member(@user, action: :write)
      new_repository.add_member(@user, action: :write)

      transfer = IssueTransfer.new(old_issue: @parent, old_repository: @repo, new_repository:, actor: @user)
      transfer.send(:create_copy_issue)


      SubIssue.build(
        source_issue_id: @parent.id,
        source_repository_id: @parent.repository_id,
        target_issue_id: @child1.id,
        actor_id: @user.id,
        priority: 1
      ).save(validate: false)

      assert_raises(StandardError, "Failed to add sub-issue: Source cannot update sub-issues while a transfer is in-progress") do
        @parent.sub_issue_relations.first.update!(priority: 2)
      end
      assert_equal 1, GitHub.dogstats.increments("sub_issue.update_during_transfer_attempted").length
    end
  end

  context "sub-issue list height" do
    test "updates list height as children are added" do
      @parent.add_sub_issue!(@child1, @user.id)
      assert_equal 1, @parent.sub_issue_list.reload.height

      @child1.add_sub_issue!(@child2, @user.id)
      assert_equal 1, @child1.sub_issue_list.reload.height
      assert_equal 2, @parent.sub_issue_list.reload.height

      @child2.add_sub_issue!(@child3, @user.id)
      assert_equal 1, @child2.sub_issue_list.reload.height
      assert_equal 2, @child1.sub_issue_list.reload.height
      assert_equal 3, @parent.sub_issue_list.reload.height
    end

    test "updates list height when one hierarchy is added to another" do
      issues = create_hierarchy!("
      - parent
        - child 1
          - child 2
      ", repository: @parent.repository)

      issues2 = create_hierarchy!("
      - parent
        - child 1
          - child 2
      ", repository: @parent.repository)

      assert_equal 2, issues["parent"]&.sub_issue_list&.height
      assert_equal 2, issues2["parent"]&.sub_issue_list&.height

      T.must(issues["child 2"]).add_sub_issue!(T.must(issues2["parent"]), @user.id)

      heights = issues.transform_values { |issue| issue.reload.sub_issue_list&.height }
      expected_heights = {
        "parent" => 5,
        "child 1" => 4,
        "child 2" => 3,
      }

      assert_equal expected_heights, heights

      heights = issues2.transform_values { |issue| issue.reload.sub_issue_list&.height }
      expected_heights = {
        "parent" => 2,
        "child 1" => 1,
        "child 2" => nil,
      }

      assert_equal expected_heights, heights
    end

    test "doesn't update any heights when a sub-issue with a smaller max-height is added" do
      issues = create_hierarchy!("
      - parent
        - child 1
          - child 2
            - child 3
              - child 4
      ", repository: @parent.repository)

      issues2 = create_hierarchy!("
      - parent.2
        - child 1.2
          - child 2.2
      ", repository: @parent.repository)


      heights_before = issues.merge(issues2).transform_values { |issue| issue.reload.sub_issue_list&.height }
      expected_heights = {
        "parent" => 4,
        "child 1" => 3,
        "child 2" => 2,
        "child 3" => 1,
        "child 4" => nil,
        "parent.2" => 2,
        "child 1.2" => 1,
        "child 2.2" => nil,
      }
      assert_equal expected_heights, heights_before

      # ensure that the sub_issue_lists table isn't updated at all, since no heights should change
      updated_tables = log_updated_tables do
        T.must(issues["child 1"]).add_sub_issue!(T.must(issues2["parent.2"]), @user.id)
      end
      refute_includes updated_tables, "sub_issue_lists"

      # reassert that all of the heights haven't changed
      heights_after = issues.merge(issues2).transform_values { |issue| issue.reload.sub_issue_list&.height }
      assert_equal heights_before, heights_after
    end

    test "efficiently prevents a tree of max height to be added as a child to another issue" do
      unable_to_add_child = create(:issue, title: "unable to add child", repository: @parent.repository)
      issues = create_hierarchy!("
      - parent
        - child 1
          - child 2
            - child 3
              - child 4
                - child 5
                  - child 6
                    - child 7
      ", repository: @parent.repository)

      assert_equal 7, issues["parent"]&.sub_issue_list&.height
      heights = issues.transform_values { |issue| issue.reload.sub_issue_list&.height }
      expected_heights = {
        "parent" => 7,
        "child 1" => 6,
        "child 2" => 5,
        "child 3" => 4,
        "child 4" => 3,
        "child 5" => 2,
        "child 6" => 1,
        "child 7" => nil,
      }
      assert_equal expected_heights, heights

      assert_raises_with_message(StandardError, "You can’t add more than 7 layers of sub-issues. To add a sub-issue, remove a parent issue at any level.") do
        assert_query_count_per_table({ sub_issue_lists: 1, sub_issues: 1 }) do
          unable_to_add_child.add_sub_issue!(T.must(issues["parent"]), @user.id)
        end
      end

      assert_equal 1, GitHub.dogstats.increments("sub_issue.maximum_height_hit").length
    end

    test "doesn't allow the creation of a sub-issue which would lead to a height greater than 7" do
      issues = create_hierarchy!("
      - parent
        - child 1
          - child 2
            - child 3
              - child 4
      ", repository: @parent.repository)

      issues2 = create_hierarchy!("
      - parent
        - child 1
          - child 2
            - child 3
              - child 4
      ", repository: @parent.repository)

      assert_raises(StandardError, "Failed to add sub-issue: may not create a hierarchy of height greater than 8") do
        T.must(issues["child 4"]).add_sub_issue!(T.must(issues2["parent"]), @user.id)
      end

      assert_equal 1, GitHub.dogstats.increments("sub_issue.maximum_height_hit").length
    end

    test "maintains sub-issue height on removal" do
      issues = create_hierarchy!("
      - parent
        - child 1
          - child 2
            - child 3
              - child 4
                - child 5
      ", repository: @parent.repository)

      heights = issues.transform_values { |issue| issue.sub_issue_list&.height }
      expected_heights = {
        "parent" => 5,
        "child 1" => 4,
        "child 2" => 3,
        "child 3" => 2,
        "child 4" => 1,
        "child 5" => nil,
      }
      assert_equal expected_heights, heights

      T.must(issues["child 2"]).remove_sub_issue!(T.must(issues["child 3"]))

      heights = issues.transform_values { |issue| issue.reload.sub_issue_list&.height }
      expected_heights = {
        "parent" => 2,
        "child 1" => 1,
        "child 2" => 0,
        "child 3" => 2,
        "child 4" => 1,
        "child 5" => nil,
      }
      assert_equal expected_heights, heights
    end

    test "bail early in the case that the removed list is not the tallest list amongst it's siblings" do
      # The following hierarchy highlights this scenario:
      # We want to make sure that we never begin traveling up-hierarchy if a removal doesn't affect any
      # heights in a tree. So, when removing child 3.2 from child 2, no calls to update any heights should
      # be performed, as child 3.2 isn't the tallest branch amongst it's siblings (child 3.1 is taller)
      hierarchy =  <<~HIERARCHY
      - parent
        - child 1
          - child 2
            - child 3.1
              - child 4.1
                - child 5.1
                  - child 6.1
            - child 3.2
              - child 4.2
                - child 5.2
            - child 3.3
              - child 4.3
      HIERARCHY

      issues = create_hierarchy!(hierarchy, repository: @parent.repository)

      heights_before = issues.transform_values { |issue| issue.sub_issue_list&.height }
      expected_heights = {
        "parent" => 6,
        "child 1" => 5,
        "child 2" => 4,
        "child 3.1" => 3,
        "child 4.1" => 2,
        "child 5.1" => 1,
        "child 6.1" => nil,
        "child 3.2" => 2,
        "child 4.2" => 1,
        "child 5.2" => nil,
        "child 3.3" => 1,
        "child 4.3" => nil,
      }
      assert_equal expected_heights, heights_before

      updated_tables = log_updated_tables do
        T.must(issues["child 2"]).remove_sub_issue!(T.must(issues["child 3.2"]))
      end
      refute_includes updated_tables, "sub_issue_lists"


      heights_after = issues.transform_values { |issue| issue.reload.sub_issue_list&.height }
      assert_equal heights_before, heights_after
    end

    test "bails when going up hierarchy when there is a taller tree" do
      # The following hierarchy highlights this scenario:
      # We want to ensure that the algorithm to update heights appropriately stops when it encounters
      # a sub-tree that already has a larger height, and no longer needs updating up-hierarchy
      # So, in this scenario, we plan to remove child 4.2 from child 3.2, once child 1 is reached while
      # progressing up the hierarchy, the algorithm should bail, seeing that this height would not be affected
      # as child 2.2 wasn't the tallest branch from child 1
      issues = create_hierarchy!("
      - parent
        - child 1
          - child 2.1
            - child 3.1
              - child 4.1
                - child 5.1
                  - child 6.1
                    - child 7.1
          - child 2.2
            - child 3.2
              - child 4.2
                - child 5.2
                  - child 6.2
            - child 3.3
              - child 4.3
                - child 5.3
            - child 3.4
              - child 4.4
      ", repository: @parent.repository)

      heights = issues.transform_values { |issue| issue.sub_issue_list&.height }
      expected_heights = {
        "parent" => 7,
        "child 1" => 6,
        "child 2.1" => 5,
        "child 3.1" => 4,
        "child 4.1" => 3,
        "child 5.1" => 2,
        "child 6.1" => 1,
        "child 7.1" => nil,
        "child 2.2" => 4,
        "child 3.2" => 3,
        "child 4.2" => 2,
        "child 5.2" => 1,
        "child 6.2" => nil,
        "child 3.3" => 2,
        "child 4.3" => 1,
        "child 5.3" => nil,
        "child 3.4" => 1,
        "child 4.4" => nil,
      }
      assert_equal expected_heights, heights

      # we should update the table 2 times:
      # - 3.2's height should be changed to 0
      # - 2.2's height should be changed to 3
      updated_tables = log_updated_tables do
        T.must(issues["child 3.2"]).remove_sub_issue!(T.must(issues["child 4.2"]))
      end

      assert_equal 2, updated_tables.count("sub_issue_lists")


      heights = issues.transform_values { |issue| issue.reload.sub_issue_list&.height }
      expected_updated_heights = {
        "child 3.2" => 0,
        "child 2.2" => 3,
      }
      assert_equal expected_heights.merge(expected_updated_heights), heights
    end
  end

  context "audit log" do
    test "instruments event when sub-issue is created" do
      assert_performed_audit_entries(count: 2, only: ["sub_issues.sub_issue_add", "sub_issues.parent_issue_add"]) do
        @parent.add_sub_issue!(@child1, @user.id)
      end
    end

    test "instruments event when sub-issue is removed" do
      @parent.add_sub_issue!(@child1, @user.id)
      assert_performed_audit_entries(count: 2, only: ["sub_issues.sub_issue_remove", "sub_issues.parent_issue_remove"]) do
        @parent.remove_sub_issue!(@child1)
      end
    end

    test "instruments event when sub-issue is destroyed" do
      @parent.add_sub_issue!(@child1, @user.id)
      perform_enqueued_jobs(only: DestroyDependentRecordsJob) do
        assert_performed_audit_entries(count: 2, only: ["sub_issues.sub_issue_remove", "sub_issues.parent_issue_remove"]) do
          @child1.destroy!
        end
      end
    end

    test "instruments event when parent issue is destroyed" do
      @parent.add_sub_issue!(@child1, @user.id)
      @parent.add_sub_issue!(@child2, @user.id)
      perform_enqueued_jobs(only: DestroyDependentRecordsJob) do
        # 2 sub-issues removed from parent + parent removed from 2 sub-issues
        assert_performed_audit_entries(count: 4, only: ["sub_issues.sub_issue_remove", "sub_issues.parent_issue_remove"]) do
          @parent.destroy!
        end
      end
    end
  end

  context "reindex issues" do
    test "reindexes issues when sub-issues are added" do
      Search.expects(:add_to_search_index).with("issue", @parent.id).at_least_once
      Search.expects(:add_to_search_index).with("issue", @child1.id).at_least_once

      @parent.add_sub_issue!(@child1, @user.id)
    end

    test "reindexes issues when sub-issues are removed" do
      @parent.add_sub_issue!(@child1, @user.id)

      Search.expects(:add_to_search_index).with("issue", @parent.id).once
      Search.expects(:add_to_search_index).with("issue", @child1.id).once

      @parent.remove_sub_issue!(@child1)
    end

    test "reindexes issues when sub-issues are deleted" do
      @parent.add_sub_issue!(@child1, @user.id)

      Search.expects(:add_to_search_index).with("issue", @child1.id).once

      perform_enqueued_jobs(only: DestroyDependentRecordsJob) do
        @parent.destroy!
      end
    end

    test "reindexes issues when sub-issues are transfered" do
      new_repository = create(:repository, owner: @org)
      @repo.add_member(@user, action: :write)
      new_repository.add_member(@user, action: :write)

      @parent.add_sub_issue!(@child1, @user.id)

      Search.expects(:add_to_search_index).at_least_once
      Search.expects(:add_to_search_index).with("issue", @child1.id).once

      transfer = IssueTransfer.new(old_issue: @parent, old_repository: @repo, new_repository:, actor: @user)
      transfer.transfer!
    end
  end
end
