# typed: true
# frozen_string_literal: true

require "test_helper"

class WorkflowLimitsDependencyTest < GitHub::TestCase
  fixtures do
    @project = create(:memex_project)
    @repo = create(:repository, owner: @project.owner)
  end

  sig { params(owner: User, limit: Integer).void }
  def assert_auto_add_limits(owner, limit)
    # test that limits are per project
    2.times do
      memex = create(:memex_project, owner: owner)

      limit.times do |i|
        get_issues_action = create(:memex_project_workflow_action, :with_arguments, action_type: :get_items, arguments: { "query" => "is:issue is:open bug#{i}", "repositoryId" => @repo.id })
        add_items_action = create(:memex_project_workflow_action, :with_arguments, action_type: :add_project_item, arguments: { "repositoryId" => @repo.id })
        workflow = build(:memex_project_workflow,
          name: "Add Item on Issue Create #{i}",
          memex_project: memex,
          actions: [get_issues_action, add_items_action],
          trigger_type: :query_matched,
        )

        assert workflow.save
      end

      get_issues_action = create(:memex_project_workflow_action, :with_arguments, action_type: :get_items, arguments: { "query" => "is:issue is:open bug#{limit + 1}", "repositoryId" => @repo.id })
      add_items_action = create(:memex_project_workflow_action, :with_arguments, action_type: :add_project_item, arguments: { "repositoryId" => @repo.id })
      workflow = build(:memex_project_workflow,
        name: "Add Item on Issue Create #{limit + 1}",
        memex_project: memex,
        actions: [get_issues_action, add_items_action],
        trigger_type: :query_matched,
      )

      refute workflow.save
      assert_includes workflow.errors.full_messages, "The workflow \"#{workflow.name}\" exceeds the maximum of #{limit} workflows for its type"
    end
  end

  test "doest not allow exceeding default creation limit of 1 workflow per type" do
    create(:memex_project_workflow, memex_project: @project, trigger_type: :item_added, content_types: ["Issue"])
    workflow = build(:memex_project_workflow, memex_project: @project, trigger_type: :item_added, content_types: ["Issue"])

    refute workflow.save
    assert_includes workflow.errors.full_messages, "The workflow \"#{workflow.name}\" exceeds the maximum of 1 workflows for its type"
  end

  context "auto add" do
    test "allows free user to create 1 workflow" do
      user = create(:user)
      assert_auto_add_limits(user, 1)
    end unless GitHub.enterprise?

    test "allows teams to create 5 workflows" do
      business_org = create(:business_organization)
      assert_auto_add_limits(business_org, 5)
    end unless GitHub.enterprise?

    test "allows pro user to create 5 workflows" do
      pro_user = create(:user, :paid_plan)
      assert_auto_add_limits(pro_user, 5)
    end unless GitHub.enterprise?

    test "allows GHEC to create 20 workflows" do
      ghec_org = create(:business_plus_organization)
      assert_auto_add_limits(ghec_org, 20)
    end unless GitHub.enterprise?

    test "allows enterprise users to create 20 workflows" do
      user = create(:user)
      assert_auto_add_limits(user, 20)
    end if GitHub.enterprise?
  end
end
