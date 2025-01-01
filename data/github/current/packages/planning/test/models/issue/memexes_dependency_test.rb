# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueMemexesTest < GitHub::TestCase
  include MemexHelpers

  fixtures do
    @owner        = create :user, :verified, login: "owner", plan: "large"
    @unauthed     = create :user, login: "unauthed"
    @org          = create :organization
    @org.add_member(@owner)

    @org_memex = create :memex_project, owner: @org, title: "first-org-memex"
    @another_org_memex = create :memex_project, owner: @org, title: "second-org-memex"
    @third_org_memex = create :memex_project, owner: @org, title: "third-org-memex"
    @deleted_memex = create :memex_project, owner: @org, title: "deleted-memex", deleted_at: Time.now

    @user_memex = create :memex_project, owner: @owner, title: "first-org-memex"
    @another_user_memex = create :memex_project, owner: @owner, title: "second-org-memex"
    @third_user_memex = create :memex_project, owner: @owner, title: "third-org-memex"

    @repo         = create :repository, owner: @owner
    @open_issue   = create :issue, repository: @repo, user: @repo.owner

    @public_repo  = create(:public_repository, owner: @unauthed)
    @public_issue = create :issue, repository: @public_repo, user: @public_repo.owner

    @org_repo      = create :repository, owner: @org
    @org_milestone = create :milestone, repository: @org_repo
    @org_issue     = create :issue, repository: @org_repo, milestone: @org_milestone

    MemexHelpers.setup_organization_wide_access_for_projects("project_writer")
  end

  context "#memex_projects_enabled?" do
    test "returns true if the new projects feature is enabled" do
      assert_equal true, @org_issue.memex_projects_enabled?
    end

    test "returns false if the new projects feature is disabled" do
      memex_disable

      assert_equal false, @open_issue.memex_projects_enabled?
    end
  end

  context "#visible_memex_items_for" do
    test "associations are preloaded for memex_projects and users tables" do
      additional_org = create :organization
      additional_memex = create :memex_project, owner: additional_org, public: true, title: "first-org-public-memex"
      org_public_memex = create :memex_project, owner: @org, public: true, title: "first-org-public-memex"
      items = [@org_memex, @another_org_memex, org_public_memex, additional_memex].map { |m| create(:memex_project_item, memex_project: m, content: @org_issue) }

      assert_query_count_per_table({ memex_projects: 1, users: 1 }) do
        @org_issue.visible_memex_items_for(@owner, allowed_owner: "github")
      end
    end

    context "#granular permissions enabled" do
      test "returns all memex_project_items if user is a member of the org" do
        items = [@org_memex, @another_org_memex].map { |m| create(:memex_project_item, memex_project: m, content: @org_issue) }
        visible_items = @org_issue.visible_memex_items_for(@owner)

        assert_same_elements [@org_memex.id, @another_org_memex.id], visible_items.map { |m| m.memex_project_id }
      end

      test "returns only memexes the user has access to" do
        org_2 = create :organization
        org2_memex = create :memex_project, owner: org_2, title: "second-org-memex"

        items = [@org_memex, org2_memex].map { |m| create(:memex_project_item, memex_project: m, content: @org_issue) }
        visible_items = @org_issue.visible_memex_items_for(@owner)

        assert_same_elements [@org_memex.id], visible_items.map { |m| m.memex_project_id }
      end

      test "return only memexes from the parent org of the issue" do
        org_2 = create :organization
        org_2.add_member(@owner)
        org2_memex = create :memex_project, owner: org_2, title: "second-org-memex"

        items = [@org_memex, org2_memex].map { |m| create(:memex_project_item, memex_project: m, content: @org_issue) }
        visible_items = @org_issue.visible_memex_items_for(@owner)

        assert_same_elements [@org_memex.id], visible_items.map { |m| m.memex_project_id }
      end

      test "does not return org-owned memexes if user is member of the org and org permission level is NONE" do
        org_2 = create :organization
        org_2.add_member(@owner)

        org2_memex = create :memex_project, owner: org_2, title: "second-org-memex"
        MemexHelpers::setup_organization_wide_access("none", org2_memex)

        items = [@org_memex, org2_memex].map { |m| create(:memex_project_item, memex_project: m, content: @org_issue) }
        visible_items = @org_issue.visible_memex_items_for(@owner)

        assert_same_elements [@org_memex.id], visible_items.map { |m| m.memex_project_id }
      end

      test "returns org-owned memexes if user is not member of the org but has individual permissions granted" do
        skip "skip this test until we allow outside collaborators"

        org_2 = create :organization
        org2_memex = create :memex_project, :with_reader, reader: @owner, owner: org_2, title: "second-org-memex"

        items = [@org_memex, org2_memex].map { |m| create(:memex_project_item, memex_project: m, content: @org_issue) }
        visible_items = @org_issue.visible_memex_items_for(@owner)

        assert_same_elements [@org_memex.id, org2_memex.id], visible_items.map { |m| m.memex_project_id }
      end

      test "does not return org-owned public memexes form another org" do
        non_member = create(:verified_user)

        org_2 = create :organization
        org2_memex = create :memex_project, owner: org_2, title: "second-org-memex", public: true

        items = [@org_memex, org2_memex].map { |m| create(:memex_project_item, memex_project: m, content: @org_issue) }
        visible_items = @org_issue.visible_memex_items_for(non_member)

        assert_empty visible_items
      end

      test "returns org-owned public memexes if user is anonymous" do
        org_public_memex = create :memex_project, owner: @org, title: "second-org-memex", public: true

        items = [@org_memex, org_public_memex].map { |m| create(:memex_project_item, memex_project: m, content: @org_issue) }
        visible_items = @org_issue.visible_memex_items_for(nil)

        assert_same_elements [org_public_memex.id], visible_items.map { |m| m.memex_project_id }
      end

      test "prefills is_template? method on memex projects" do
        org_public_memex = create :memex_project, owner: @org, public: true
        memex_template = create :memex_template, memex_project: org_public_memex
        create(:memex_project_item, memex_project: org_public_memex, content: @org_issue)

        assert_query_count_per_table({ memex_templates: 0 }) do
          @org_issue.visible_memex_items_for(nil, prefill_template_predicate: false)
        end

        assert_query_count_per_table({ memex_templates: 1 }) do
          @org_issue.visible_memex_items_for(nil, prefill_template_predicate: true)
        end
      end
    end

    context "user owned memexes" do
      test "returns memex items when memex is enabled" do
        items = [@user_memex, @another_user_memex].map { |m| create(:memex_project_item, memex_project: m, content: @open_issue) }
        visible_items = @open_issue.visible_memex_items_for(@owner)

        assert_same_elements items, visible_items
      end

      test "omits memex items when memex is disabled" do
        memex_disable

        items = [@user_memex, @another_user_memex].map { |m| create(:memex_project_item, memex_project: m, content: @open_issue) }
        visible_items = @open_issue.visible_memex_items_for(@owner)

        assert_empty visible_items
      end

      test "does not returns memex items not owned by the issue owner" do
        item = create(:memex_project_item, memex_project: @user_memex, content: @public_issue)
        visible_items = @public_issue.visible_memex_items_for(@owner)

        assert_empty visible_items
      end

      test "return memex items for collaborator with read access" do
        collaborator = create(:verified_user)
        @user_memex.grant_role(collaborator, :reader)

        item = create(:memex_project_item, memex_project: @user_memex, content: @open_issue)

        visible_items = @open_issue.visible_memex_items_for(collaborator)
        assert_same_elements [item], visible_items
      end

      test "omits memex items for users without read access" do
        collaborator = create(:verified_user)
        item = create(:memex_project_item, memex_project: @user_memex, content: @open_issue)

        visible_items = @open_issue.visible_memex_items_for(collaborator)
        assert_empty visible_items
      end

      test "can include and exclude archived items" do
        item = create(:memex_project_item, memex_project: @user_memex, content: @open_issue, archived_at: 1.day.ago, archiver: @owner)

        assert_equal [item], @open_issue.visible_memex_items_for(@owner, include_archived: true)
        assert_empty @open_issue.visible_memex_items_for(@owner, include_archived: false)
      end
    end

    context "org owned memexes" do
      test "returns all memex_project_items if user is a member of the org and memex is enabled" do
        items = [@org_memex, @another_org_memex].map { |m| create(:memex_project_item, memex_project: m, content: @org_issue) }
        visible_items = @org_issue.visible_memex_items_for(@owner)

        assert_same_elements items, visible_items
        assert visible_items.all? { |i| i.association(:memex_project).loaded? }, \
          "MemexProject must be preloaded along with memex_project_items"
      end

      test "returns all memex_project_items for org memexes associated with the pull request if issue is a PR" do
        pull = create(:pull_request, :disable_disk_access, repository: @org_repo)
        items = [@org_memex, @another_org_memex].map { |m| create(:memex_project_item, memex_project: m, content: pull) }
        visible_items = pull.issue.visible_memex_items_for(@owner)

        assert_same_elements items, visible_items
        assert visible_items.all? { |i| i.association(:memex_project).loaded? }, \
          "MemexProject must be preloaded along with memex_project_items"
      end

      test "returns all memex_project_items for user memexes associated with the pull request if issue is a PR" do
        pull = create(:pull_request, :disable_disk_access, repository: @repo)
        items = [@user_memex, @another_user_memex].map { |m| create(:memex_project_item, memex_project: m, content: pull) }
        visible_items = pull.issue.visible_memex_items_for(@owner)

        assert_same_elements items, visible_items
        assert visible_items.all? { |i| i.association(:memex_project).loaded? }, \
          "MemexProject must be preloaded along with memex_project_items"
      end

      test "returns an empty array if viewer is not a member of the org" do
        items = [@org_memex, @another_org_memex].map { |m| create(:memex_project_item, memex_project: m, content: @org_issue) }
        assert_empty @org_issue.visible_memex_items_for(@unauthed)
      end

      test "does not return a cross-org memex item when the viewer is a member of both orgs" do
        org = create(:organization)
        org.add_member(@owner)

        memex = create(:memex_project, owner: org)
        item = create(:memex_project_item, content: @org_issue, memex_project: memex)

        visible_items = @org_issue.visible_memex_items_for(@owner)
        assert_empty visible_items
      end

      test "omits a cross-org memex item when the viewer is not in the memex's org" do
        org = create(:organization)

        memex = create(:memex_project, owner: org)
        item = create(:memex_project_item, content: @org_issue, memex_project: memex)

        visible_items = @org_issue.visible_memex_items_for(@owner)
        assert_empty visible_items
      end

      test "returns memex items from the same owner only" do
        org1 = create :organization
        org1.add_member(@owner)
        org1_memex = create :memex_project, owner: org1

        items = [@org_memex, @another_org_memex, org1_memex].map { |m| create(:memex_project_item, memex_project: m, content: @org_issue) }
        visible_items = @org_issue.visible_memex_items_for(@owner)

        assert_same_elements items.take(2), visible_items
      end

      test "returns memex items from another custom owner" do
        org1 = create :organization
        org1.add_member(@owner)
        org1_memex = create :memex_project, owner: org1

        org2 = create :organization
        org2.add_member(@owner)
        org2_memex = create :memex_project, owner: org2

        items = [@org_memex, @another_org_memex, org1_memex, org2_memex].map { |m| create(:memex_project_item, memex_project: m, content: @org_issue) }
        visible_items = @org_issue.visible_memex_items_for(@owner, allowed_owner: org1.display_login)

        assert_same_elements items.take(3), visible_items
      end

      test "returns an empty array if memex is not enabled" do
        memex_disable
        items = [@org_memex, @another_org_memex].map { |m| create(:memex_project_item, memex_project: m, content: @org_issue) }
        visible_items = @org_issue.visible_memex_items_for(@owner)

        assert_empty visible_items
      end

      test "returns public memex_project_items if user is not a member of the org" do
        org_public_memex = create :memex_project, owner: @org, public: true, title: "first-org-public-memex"

        items = [org_public_memex].map { |m| create(:memex_project_item, memex_project: m, content: @org_issue) }
        visible_items = @org_issue.visible_memex_items_for(@unauthed)

        assert_same_elements items, visible_items
        assert visible_items.all? { |i| i.association(:memex_project).loaded? }, \
          "MemexProject must be preloaded along with memex_project_items"
      end

      test "returns public memex_project_items if user is anonymous and" do
        org_public_memex = create :memex_project, owner: @org, public: true, title: "first-org-public-memex"

        items = [org_public_memex].map { |m| create(:memex_project_item, memex_project: m, content: @org_issue) }
        visible_items = @org_issue.visible_memex_items_for(nil)

        assert_same_elements items, visible_items
        assert visible_items.all? { |i| i.association(:memex_project).loaded? }, \
          "MemexProject must be preloaded along with memex_project_items"
      end

      test "returns both private and public memex_project_items if user is a member of the org and memex enabled" do
        org_public_memex = create :memex_project, owner: @org, public: true, title: "first-org-public-memex"

        items = [@org_memex, @another_org_memex, org_public_memex].map { |m| create(:memex_project_item, memex_project: m, content: @org_issue) }
        visible_items = @org_issue.visible_memex_items_for(@owner)

        assert_same_elements items, visible_items
        assert visible_items.all? { |i| i.association(:memex_project).loaded? }, \
          "MemexProject must be preloaded along with memex_project_items"
      end

      test "returns an empty array if issue is not owned by an org" do
        memex_disable

        items = [@org_memex, @another_org_memex].map { |m| create(:memex_project_item, memex_project: m, content: @open_issue) }
        assert_empty @open_issue.visible_memex_items_for(@owner)
      end

      test "can include or exclude archived items" do
        item = create(:memex_project_item, memex_project: @org_memex, content: @org_issue, archived_at: 1.day.ago, archiver: @owner)

        assert_same_elements [item], @org_issue.visible_memex_items_for(@owner, include_archived: true)
        assert_empty @org_issue.visible_memex_items_for(@owner, include_archived: false)
      end
    end

    test "calls async_visible_items_for with correct arguments and syncs" do
      @org_issue.expects(:async_visible_memex_items_for).with(
        @owner,
        include_archived: true,
        allowed_owner: nil,
        prefill_template_predicate: false,
      ).returns(Promise.resolve(["Hello", "I", "Am" "A", "Memex"]))

      assert_equal ["Hello", "I", "Am" "A", "Memex"], @org_issue.visible_memex_items_for(@owner)
    end
  end

  context "#async_visible_memex_items_for" do
    test "returns a Promise resolving to visible memex project items" do
      items = [@org_memex, @another_org_memex].map { |m| create(:memex_project_item, memex_project: m, content: @org_issue) }
      visible_items = @org_issue.async_visible_memex_items_for(@owner)

      assert_kind_of Promise, visible_items
      assert_same_elements items, visible_items.sync
      assert_same_elements @org_issue.visible_memex_items_for(@owner), visible_items.sync
    end

    test "returns a Promise resolving to visible memex project items even if repository does not have the projects feature enabled" do
      @org_repo.disable_repository_memex_projects(actor: @owner)

      items = [@org_memex, @another_org_memex].map { |m| create(:memex_project_item, memex_project: m, content: @org_issue) }
      visible_items = @org_issue.async_visible_memex_items_for(@owner)

      assert_kind_of Promise, visible_items
      assert_same_elements items, visible_items.sync
      assert_same_elements @org_issue.visible_memex_items_for(@owner), visible_items.sync
    end

    test "filters out items for deleted projects" do
      items = [@org_memex, @another_org_memex].map { |m| create(:memex_project_item, memex_project: m, content: @org_issue) }
      item_for_deleted_project = create(:memex_project_item, memex_project: @deleted_memex, content: @org_issue)
      visible_items = @org_issue.async_visible_memex_items_for(@owner)

      assert_kind_of Promise, visible_items
      assert_same_elements items, visible_items.sync
      assert_same_elements @org_issue.visible_memex_items_for(@owner), visible_items.sync
    end
  end

  context "#memex_suggestion_hash" do
    test "dumps relevant attributes of the object" do
      # Fri, March 6, 2020 8pm UTC.
      updated_at = Time.utc(2020, 3, 06, 20, 00, 00)

      issue = create(
        :issue,
        repository: @public_repo,
        title: "The Master Plan",
        updated_at: updated_at,
      )

      sub_issue = create(
        :issue,
        repository: @public_repo,
        title: "The Executor",
        updated_at: updated_at,
      )

      issue.add_sub_issue!(sub_issue, @public_repo.owner.id)

      expected_hash = {
        id: issue.id,
        lastInteractionAt: nil,
        number: issue.number,
        state: "open",
        stateReason: nil,
        title: "The Master Plan",
        type: "Issue",
        updatedAt: "2020-03-06T20:00:00Z",
        hasSubIssues: true
      }

      assert_equal expected_hash, issue.memex_suggestion_hash
    end

    test "can approximate a pull request suggestion hash" do
      pull = create(
        :pull_request,
        :disable_disk_access,
        work_in_progress: true,
        repository: @public_repo,
        user: @unauthed,
      ).tap do |p|
        p.issue.title = "The Antidote"
        p.issue.save!
      end

      expected_hash = {
        id: pull.id,
        lastInteractionAt: nil,
        number: pull.number,
        state: "open",
        title: "The Antidote",
        type: "PullRequest",

        # These are expected not to be accurate, hence the approximation.
        isDraft: false,
        updatedAt: pull.issue.updated_at.utc.iso8601
      }

      assert_equal expected_hash, pull.issue.memex_suggestion_hash(as_pull: true)
    end
  end

  context "#memex_content_hash" do
    test "dumps base attributes of the object" do
      issue = create(
        :issue,
        repository: @public_repo,
        title: "The Master Plan",
      )

      expected_hash = {
        id: issue.id,
        url: issue.permalink,
        globalRelayId: issue.global_relay_id,
      }

      assert_equal expected_hash, issue.memex_content_hash
    end

    test "serializes a user properly" do
      issue = create(
        :issue,
        repository: @public_repo,
        title: "The Master Plan",
      )

      expected_hash = {
        id: issue.id,
        url: issue.permalink,
        globalRelayId: issue.global_relay_id,
        user: issue.user.memex_column_hash
      }

      assert_equal expected_hash, issue.memex_content_hash(fields: [:user])
    end

    test "serializes issue nwo reference correctly" do
      issue = create(
        :issue,
        repository: @public_repo,
        title: "The Master Plan",
      )

      expected_nwo = "#{issue.repository.owner.display_login}/#{issue.repository.name}##{issue.number}"

      assert_equal expected_nwo, issue.memex_column_hash[:nwoReference]
    end

    test "handles deleted user properly" do
      issue = create(
        :issue,
        repository: @public_repo,
        title: "The Master Plan",
      )

      issue.user.destroy

      issue.reload

      expected_hash = {
        id: issue.id,
        url: issue.permalink,
        globalRelayId: issue.global_relay_id,
        user: User.ghost.memex_column_hash
      }

      assert_equal expected_hash, issue.memex_content_hash(fields: [:user])
    end
  end

  context "#csv_column_value" do
    test "returns url value for csv column" do
      issue = create(
        :issue,
        repository: @public_repo,
        title: "The Master Plan",
      )

      assert_equal issue.permalink, issue.csv_column_value
    end
  end

  context "#count_user_defined_fields" do
    test "returns the correct number of custom fields" do
      issue = create(:issue, repository: @public_repo)
      item = create(:memex_project_item, content: issue)
      memex = item.memex_project
      column = create(:memex_project_column, memex_project: memex, user_defined: true, name: "text column", data_type: :text)
      column_value = create(:memex_project_column_value, value: "value here", memex_project_column: column, memex_project_item: item)

      results = issue.count_user_defined_fields([item])
      result = results[item.memex_project.id]

      assert result
      assert_equal 1, result
    end

    test "ignores column.visible, as this no longer influences visibility" do
      issue = create(:issue, repository: @public_repo)
      item = create(:memex_project_item, content: issue)
      memex = item.memex_project
      column = create(:memex_project_column, memex_project: memex, user_defined: true, visible: false, name: "text column", data_type: :text)
      column_value = create(:memex_project_column_value, value: "value here", memex_project_column: column, memex_project_item: item)

      results = issue.count_user_defined_fields([item])
      result = results[item.memex_project.id]

      assert_equal 1, result
    end
  end

  context "#status_column_values_by_memex_item_id" do
    test "returns the correct value when status column value is set" do
      issue = create(:issue, repository: @public_repo)
      item = create(:memex_project_item, content: issue)
      memex = item.memex_project
      status_column = memex.status_column

      todo_option_id = status_column.settings["options"].find { |o| o["name"] == "Todo" }["id"]
      item.set_column_value(status_column, todo_option_id, @owner)

      results = issue.status_column_values_by_memex_item_id([item])
      result = results[item.id]

      assert result
      assert_equal status_column.id, result[:column_id]
      assert_equal "Todo", result[:option]["name"]
    end

    test "returns the correct value when status column value is set with an emoji" do
      issue = create(:issue, repository: @public_repo)
      item = create(:memex_project_item, content: issue)
      memex = item.memex_project
      status_column = memex.status_column
      status_column.settings =
        {
          "options" => [
            { name: ":rocket: test", color: "RED", description: "red" },
            { name: "foo", color: "RED", description: "red" },
            { name: "bar", color: "RED", description: "red" },
          ]
        }
      status_column.save!
      status_column.reload

      option_id = status_column.settings["options"].first["id"]
      item.set_column_value(status_column, option_id, @owner)

      results = issue.status_column_values_by_memex_item_id([item])
      result = results[item.id]

      assert result
      assert_equal status_column.id, result[:column_id]
      assert result[:option]["name_html"].include?("🚀")
    end

    test "returns the correct value when status column value is unset" do
      issue = create(:issue, repository: @public_repo)
      item = create(:memex_project_item, content: issue)
      memex = item.memex_project
      status_column = memex.status_column

      results = issue.status_column_values_by_memex_item_id([item])
      result = results[item.id]

      assert result
      assert_equal status_column.id, result[:column_id]
      assert_nil result[:option]
    end
  end

  context "#add_to_memex_projects!" do
    test "does nothing when no ids are given" do
      params = {}

      @org_issue.add_to_memex_projects!(params, @org_issue, @owner)

      assert_equal 0, @org_issue.memex_projects.size
      assert_equal 0, @org_issue.memex_project_items.size
    end

    test "creates memex project items" do
      params = {
        @org_memex.id.to_s => "on",
        @another_org_memex.id.to_s => "",
        @third_org_memex.id.to_s => "on",
      }

      @org_issue.add_to_memex_projects!(params, @org_issue, @owner)

      assert_equal 2, @org_issue.memex_project_items.length

      [@org_memex, @third_org_memex].each do |memex_project|
        item = @org_issue.memex_project_items.find { |i| i.memex_project_id == memex_project.id }

        refute_nil item, "an item should have been created for #{memex_project.title}"
        assert_equal @org_issue, item.content, "content is incorrect for item created in #{memex_project.title}"
        assert_memex_item_is_denormalized(memex_project, item)
      end
    end

    test "will unarchive any archived MemexProjectItem" do
      params = {
        @org_memex.id.to_s => "on",
      }

      item = create(:memex_project_item, memex_project: @org_memex, content: @org_issue)
      assert item.archive!

      assert_no_difference "MemexProjectItem.count" do
        @org_issue.add_to_memex_projects!(params, @org_issue, @owner)
      end

      refute_predicate item.reload, :archived?
    end

    test "for content that exists in a MemexProject is a no-op" do
      params = {
        @org_memex.id.to_s => "on",
      }

      item = create(:memex_project_item, memex_project: @org_memex, content: @org_issue)
      refute_predicate item, :archived?

      assert_no_difference "MemexProjectItem.count" do
        @org_issue.add_to_memex_projects!(params, @org_issue, @owner)
      end

      refute_predicate item.reload, :archived?
    end
  end

  context "#potential_memex_projects_for" do
    test "returns empty array if no viewer provided" do
      assert_empty @org_issue.potential_memex_projects_for(nil, ids: [@org_memex.id])
    end

    test "return orgs projects" do
      memexes = [@org_memex, @another_org_memex, @third_org_memex]
      assert_same_elements(
        memexes,
        @org_issue.potential_memex_projects_for(@owner, ids: memexes.map(&:id))
      )
    end

    test "return users projects" do
      memexes = [@user_memex, @another_user_memex, @third_user_memex]
      assert_same_elements(
        memexes,
        @open_issue.potential_memex_projects_for(@owner, ids: memexes.map(&:id))
      )
    end

    test "filters out orgs closed projects" do
      closed_org_memex = create :memex_project, owner: @org, closed_at: DateTime.now
      assert_same_elements(
        [@org_memex, @another_org_memex, @third_org_memex],
        @org_issue.potential_memex_projects_for(
          @owner,
          ids: [@org_memex.id, @another_org_memex.id, @third_org_memex.id, closed_org_memex.id]
        )
      )
    end

    test "filters out users closed projects" do
      closed_user_memex = create :memex_project, owner: @owner, closed_at: DateTime.now
      assert_same_elements(
        [@user_memex, @another_user_memex, @third_user_memex],
        @open_issue.potential_memex_projects_for(
          @owner,
          ids: [@user_memex.id, @another_user_memex.id, @third_user_memex.id, closed_user_memex.id]
        )
      )
    end

    test "filters out orgs deleted projects" do
      deleted_org_memex = create :memex_project, owner: @org, deleted_at: DateTime.now
      assert_same_elements(
        [@org_memex, @another_org_memex, @third_org_memex],
        @org_issue.potential_memex_projects_for(
          @owner,
          ids: [@org_memex.id, @another_org_memex.id, @third_org_memex.id, deleted_org_memex.id]
        )
      )
    end

    test "filters out users deleted projects" do
      deleted_user_memex = create :memex_project, owner: @owner, deleted_at: DateTime.now
      assert_same_elements(
        [@user_memex, @another_user_memex, @third_user_memex],
        @open_issue.potential_memex_projects_for(
          @owner,
          ids: [@user_memex.id, @another_user_memex.id, @third_user_memex.id, deleted_user_memex.id]
        )
      )
    end

    test "filters out memexes not owned by org owned issue owner" do
      # memex that @owner has access to but is not owned by the owner of @org_issue
      user_owned_memex = create :memex_project, owner: @owner, creator: @owner

      assert_same_elements(
        [@org_memex],
        @org_issue.potential_memex_projects_for(
          @owner,
          ids: [@org_memex.id, user_owned_memex.id]
        )
      )
    end

    test "filters out memexes not owned by user owned issue owner" do
      org_owned_memex = create :memex_project, owner: @org, creator: @owner

      assert_same_elements(
        [@user_memex],
        @open_issue.potential_memex_projects_for(
          @owner,
          ids: [@user_memex.id, org_owned_memex.id]
        )
      )
    end

    test "returns org projects with org wide write access" do
      MemexHelpers::setup_organization_wide_access("project_writer", @org_memex)
      MemexHelpers::setup_organization_wide_access("project_reader", @another_org_memex)
      MemexHelpers::setup_organization_wide_access("project_writer", @third_org_memex)

      memexes = [@org_memex, @another_org_memex, @third_org_memex]
      assert_same_elements(
        [@org_memex, @third_org_memex],
        @org_issue.potential_memex_projects_for(@owner, ids: memexes.map(&:id))
      )
    end

    test "returns org projects where viewer has write access" do
      MemexHelpers::setup_organization_wide_access("project_reader", @org_memex)
      MemexHelpers::setup_organization_wide_access("project_reader", @another_org_memex)
      MemexHelpers::setup_organization_wide_access("project_reader", @third_org_memex)

      Permissions::Granters::RoleGranter.new(actor: @owner, target: @org_memex, role: Role.project_writer_role).grant_unless_exists!
      Permissions::Granters::RoleGranter.new(actor: @owner, target: @another_org_memex, role: Role.project_reader_role).grant_unless_exists!
      Permissions::Granters::RoleGranter.new(actor: @owner, target: @third_org_memex, role: Role.project_writer_role).grant_unless_exists!

      memexes = [@org_memex, @another_org_memex, @third_org_memex]
      assert_same_elements(
        [@org_memex, @third_org_memex],
        @org_issue.potential_memex_projects_for(@owner, ids: memexes.map(&:id))
      )
    end

    test "skips org projects where viewer has no access" do
      MemexHelpers::setup_organization_wide_access("project_reader", @org_memex)
      MemexHelpers::setup_organization_wide_access("project_reader", @another_org_memex)
      MemexHelpers::setup_organization_wide_access("project_reader", @third_org_memex)

      memexes = [@org_memex, @another_org_memex, @third_org_memex]
      assert_same_elements(
        [],
        @org_issue.potential_memex_projects_for(@owner, ids: memexes.map(&:id))
      )
    end

    test "returns user projects where collaborator has write access" do
      collaborator = create(:verified_user)

      Permissions::Granters::RoleGranter.new(actor: collaborator, target: @user_memex, role: Role.project_writer_role).grant_unless_exists!
      Permissions::Granters::RoleGranter.new(actor: collaborator, target: @third_user_memex, role: Role.project_writer_role).grant_unless_exists!

      memexes = [@user_memex, @another_user_memex, @third_user_memex]
      assert_same_elements(
        [@user_memex, @third_user_memex],
        @open_issue.potential_memex_projects_for(collaborator, ids: memexes.map(&:id))
      )
    end

    test "uses :batching authorisation method when checking up to 30 items" do
      @open_issue.repository.owner.expects(:accessible_memexes_scope).with(anything, anything, anything, :batching).times(1).returns(MemexProject.none)
      @open_issue.repository.owner.expects(:accessible_memexes_scope).with(anything, anything, anything, :enumeration).never

      @open_issue.potential_memex_projects_for(@owner, ids: (1..30).to_a)
    end

    test "uses :enumeration authorisation method when checking more than 30 items" do
      @open_issue.repository.owner.expects(:accessible_memexes_scope).with(anything, anything, anything, :batching).never
      @open_issue.repository.owner.expects(:accessible_memexes_scope).with(anything, anything, anything, :enumeration).times(1).returns(MemexProject.none)

      @open_issue.potential_memex_projects_for(@owner, ids: (1..31).to_a)
    end
  end

  context "#touch_memex_project_items" do
    test "touch_memex_project_items_job is enqueued when issue has been changed" do
      perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        @org_issue.update! title: "new title"
      end
      assert_enqueued_with(job: TouchMemexProjectItemsJob, args: [@org_issue])
    end

    test "touch_memex_project_items_job is enqueued for pull request when pull request's issue has been changed" do
      pr = create :pull_request, :disable_disk_access, repository: @repo
      perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        pr.issue.update! title: "new title"
      end
      assert_enqueued_with(job: TouchMemexProjectItemsJob, args: [pr])
    end
  end

  context "memex_column_hash" do
    test "returns relevant attributes" do
      updated_at = Time.utc(2020, 3, 06, 20, 00, 00)

      issue = create(
        :issue,
        repository: @public_repo,
        title: "The Master Plan `code`",
        updated_at: updated_at,
        state: "closed",
        state_reason: :not_planned
      )

      sub_issue = create(
        :issue,
        repository: @public_repo,
        title: "The Executor",
        updated_at: updated_at,
      )

      issue.add_sub_issue!(sub_issue, @public_repo.owner.id)

      expected_hash = {
        id: issue.id,
        globalRelayId: issue.global_relay_id,
        number: issue.number,
        state: "closed",
        stateReason: "not_planned",
        title: "The Master Plan `code`",
        titleHtml: "The Master Plan <code>code</code>",
        repository: @public_repo.name,
        owner: @public_repo.owner.display_login,
        nwoReference: issue.name_with_display_owner_reference,
        url: issue.url,
        subIssueList: {
          "total" => 1,
          "completed" => 0,
          "percentCompleted" => 0,
        },
        updatedAt: updated_at.utc.iso8601,
      }

      assert_equal expected_hash, issue.memex_column_hash
    end
  end
end
