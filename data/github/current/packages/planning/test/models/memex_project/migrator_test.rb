# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectMigratorTest < GitHub::TestCase
  fixtures do
    @admin = create(:verified_user)
    @org = create(:organization, admin: @admin)
    @legacy_kanban_project = create(:org_project, owner: @org).tap do |p|
      p.apply_template(ProjectTemplate::AutomatedReviewsKanban.new)
    end
    refute_empty @legacy_kanban_project.project_workflows
    @repo = create(:repository, owner: @org, from_example: :repository_test_simple)
    @project_migration = create(:project_migration, requester: @admin, project: @legacy_kanban_project)

    @opened_issue = create(:issue, repository: @repo)
    @opened_pr = create(:pull_request, :disable_disk_access, repository: @repo, user: @admin)
    @closed_issue = create(:issue, repository: @repo, state: :closed)
    @merged_pr = create(:pull_request, :with_mergeable_head, :merged, repository: @repo)
    @closed_pr = create(:pull_request, :closed, :disable_disk_access, head_ref: "closed", repository: @repo, user: @admin)
  end

  setup do
    skip if GitHub.enterprise?
    Configuration::Entry.memex_project_org_wide_role.global.create(
      value: "project_writer",
      updater: @admin,
    )
  end

  context ".migrate!" do
    test "successfully migrates the basic structure of a project" do
      kanban_column_names = ["To do", "In progress", "Review in progress", "Reviewer approved", "Done"]
      org_project = create(:org_project, owner: @org, name: "Review Board", body: "Our team review board.", public: false)
      org_project.apply_template(ProjectTemplate::AutomatedReviewsKanban.new)
      assert_equal kanban_column_names, org_project.columns.map(&:name)

      project_migration = create(:project_migration, requester: @admin, project: org_project)
      memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }
      memex.reload

      assert_equal "Review Board", memex.title
      assert_equal "Our team review board.", memex.description
      labels_column = memex.find_column_by_name_or_id("Labels")
      assert_includes memex.default_view.visible_columns, labels_column
      refute memex.public?
      assert_equal kanban_column_names, memex.status_column.settings_options.map { |o| o["name"] }
    end

    context "link project" do
      test "successfully links a migrated repository owned project for curation" do
        repo = create(:repository, owner: @org)
        legacy_project = create(:org_project, owner: repo).tap do |p|
          p.apply_template(ProjectTemplate::AutomatedReviewsKanban.new)
        end

        project_migration = create(:project_migration, requester: @admin, project: legacy_project)

        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }
        memex.reload

        suggester = ProjectSuggester.new(viewer: @admin, context: repo, load_memex_projects: true)
        assert_same_elements [memex], suggester.repository_memex_projects
      end

      test "it does not create a new link if one already exists for a project" do
        repo = create(:repository, owner: @org)
        legacy_project = create(:org_project, owner: repo).tap do |p|
          p.apply_template(ProjectTemplate::AutomatedReviewsKanban.new)
        end

        project_migration = create(:project_migration, requester: @admin, project: legacy_project)

        assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }
        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }
        memex.reload

        suggester = ProjectSuggester.new(viewer: @admin, context: repo, load_memex_projects: true)
        assert_same_elements [memex], suggester.repository_memex_projects
        assert_equal 1, memex.memex_project_links.count
      end
    end

    context "resuming a previous migration" do
      test "it does not create a new memex project if one is already associated with the project migration" do
        memex_for_migration = create(:memex_project, owner: @admin)
        project_migration = create(:project_migration, requester: @admin, project: @legacy_kanban_project, memex_project: memex_for_migration)
        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }
        assert_equal memex_for_migration.id, memex.id
      end

      test "creates a new memex project if there is not one already associated with the project migration" do
        memex_for_migration = create(:memex_project, owner: @admin)
        project_migration = create(:project_migration, requester: @admin, project: @legacy_kanban_project, memex_project: nil)
        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }
        refute_nil memex.id
      end

      test "it sends a live update event for each stage in the migration process for a newly created memex project" do
        memex_for_migration = create(:memex_project, owner: @admin)
        project_migration = create(:project_migration, requester: @admin, project: @legacy_kanban_project, memex_project: memex_for_migration)

        # One socket message for each status update - status, default view, permissions, items, workflows, completed
        GitHub::WebSocket.expects(:notify_memex_channel).times(6)

        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }
        assert_equal memex_for_migration.id, memex.id
      end

      test "it skips the first stage if the current status is in_progress_default_view" do
        memex_for_migration = create(:memex_project, owner: @admin)
        project_migration = create(:project_migration, requester: @admin, project: @legacy_kanban_project, memex_project: memex_for_migration, status: "in_progress_default_view")

        # Simulate the condition where the status field has already been migrated
        spec = @legacy_kanban_project.to_memex_specification
        memex_for_migration.configure_status_field!(spec[:status_field])

        # One socket message for each status update other than status - default view, permissions, items, workflows, completed
        GitHub::WebSocket.expects(:notify_memex_channel).times(5)

        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }
        assert_equal memex_for_migration.id, memex.id
      end

      test "it skips the first two stages if the current status is in_progress_permissions" do
        memex_for_migration = create(:memex_project, owner: @admin)
        project_migration = create(:project_migration, requester: @admin, project: @legacy_kanban_project, memex_project: memex_for_migration, status: "in_progress_permissions")

        # Simulate the condition where the first two stages are completed
        spec = @legacy_kanban_project.to_memex_specification
        memex_for_migration.configure_status_field!(spec[:status_field])
        memex_for_migration.configure_default_view!(spec[:views]&.first)

        # One socket message for eachof the remaining stages - permissions, items, workflows, completed
        GitHub::WebSocket.expects(:notify_memex_channel).times(4)

        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }
        assert_equal memex_for_migration.id, memex.id
      end

      test "it skips the first three stages if the current status is in_progress_items" do
        memex_for_migration = create(:memex_project, owner: @admin)
        project_migration = create(:project_migration, requester: @admin, project: @legacy_kanban_project, memex_project: memex_for_migration, status: "in_progress_items")

        # Simulate the condition where the first three stages are completed
        spec = @legacy_kanban_project.to_memex_specification
        memex_for_migration.configure_status_field!(spec[:status_field])
        memex_for_migration.configure_default_view!(spec[:views]&.first)
        memex_for_migration.configure_permissions!(spec[:permissions])

        # One socket message for each of the remaining stages - items, workflows, completed
        GitHub::WebSocket.expects(:notify_memex_channel).times(3)

        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }
        assert_equal memex_for_migration.id, memex.id
      end

      test "it skips the first four stages if the current status is in_progress_workflows" do
        memex_for_migration = create(:memex_project, owner: @admin)
        project_migration = create(:project_migration, requester: @admin, project: @legacy_kanban_project, memex_project: memex_for_migration, status: "in_progress_workflows")

        # Simulate the condition where the first three stages are completed
        spec = @legacy_kanban_project.to_memex_specification
        memex_for_migration.configure_status_field!(spec[:status_field])
        memex_for_migration.configure_default_view!(spec[:views]&.first)
        memex_for_migration.configure_permissions!(spec[:permissions])
        memex_for_migration.populate_items!(@admin, spec[:items], project_migration)

        # One socket message for each of the remaining stages - workflows, completed
        GitHub::WebSocket.expects(:notify_memex_channel).times(2)

        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }

        assert_equal memex_for_migration.id, memex.id
      end

      test "it skips all stages if the migration is completed" do
        memex_for_migration = create(:memex_project, owner: @admin)
        project_migration = create(:project_migration, requester: @admin, project: @legacy_kanban_project, memex_project: memex_for_migration, status: "completed")

        GitHub::WebSocket.expects(:notify_memex_channel).never

        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }
        assert_equal memex_for_migration.id, memex.id
      end

      test "it includes source project details in the web socket event" do
        memex_for_migration = create(:memex_project, owner: @admin)
        project_migration = create(:project_migration, requester: @admin, project: @legacy_kanban_project, memex_project: memex_for_migration, status: "in_progress_permissions")
        spec = @legacy_kanban_project.to_memex_specification

        expected_payload = project_migration.as_json(only: ProjectMigration::PROJECT_MIGRATION_FIELDS, methods: :is_automated)
        expected_payload["project_migration"]["source_project"] = {
          "name": @legacy_kanban_project.name,
          "closed": false,
          "path": "/orgs/#{@legacy_kanban_project.owner.login}/projects/#{@legacy_kanban_project.number}",
          "empty": @legacy_kanban_project.empty?
        }.as_json

        payload = MemexProject::Migrator.new(@admin, project_migration, spec).send(:live_update_payload, project_migration)

        assert_equal payload, expected_payload
      end
    end

    test "successfully migrates all project workflows" do
      memex = assert_nothing_raised { MemexProject::Migrator.migrate!(@project_migration.id) }
      memex.reload

      status_column = memex.status_column

      assert_same_elements(
        %w[item_added reopened review_changes_requested review_approved closed merged],
        memex.workflows.map(&:trigger_type).uniq
      )
      assert memex.workflows.all? { |w| w.actions.length == 1 }, "expected all workflows to have exactly one action"
      assert memex.workflows.all? { |w| w.actions.first.arguments["fieldId"] == status_column.id }, "expected all workflow actions to automate the status column"
    end

    test "successfully migrates item added workflows" do
      memex = assert_nothing_raised { MemexProject::Migrator.migrate!(@project_migration.id) }
      memex.reload

      status_options_by_name = memex.status_column.settings_options.index_by { |o| o[:name] }

      added_workflows = memex.workflows.find_all { |w| w.trigger_type == "item_added" }
      issue_added_workflow = added_workflows.find { |w| w.content_types == [MemexProjectItem::ISSUE_TYPE] }
      pr_added_workflow = added_workflows.find { |w| w.content_types == [MemexProjectItem::PULL_REQUEST_TYPE] }

      assert_equal 2, added_workflows.length
      assert_equal status_options_by_name["To do"][:id], issue_added_workflow.actions.first.arguments["fieldOptionId"]
      assert_equal status_options_by_name["In progress"][:id], pr_added_workflow.actions.first.arguments["fieldOptionId"]
    end

    test "successfully migrates reopened workflows" do
      memex = assert_nothing_raised { MemexProject::Migrator.migrate!(@project_migration.id) }
      memex.reload

      status_options_by_name = memex.status_column.settings_options.index_by { |o| o[:name] }

      reopened_workflows = memex.workflows.find_all { |w| w.trigger_type == "reopened" }

      assert_equal 1, reopened_workflows.length
      assert_same_elements [MemexProjectItem::ISSUE_TYPE, MemexProjectItem::PULL_REQUEST_TYPE], reopened_workflows.first.content_types
      assert_equal status_options_by_name["In progress"][:id], reopened_workflows.first.actions.first.arguments["fieldOptionId"]
    end

    test "successfully migrates request changes workflows" do
      memex = assert_nothing_raised { MemexProject::Migrator.migrate!(@project_migration.id) }
      memex.reload

      status_options_by_name = memex.status_column.settings_options.index_by { |o| o[:name] }

      request_changes_workflows = memex.workflows.find_all { |w| w.trigger_type == "review_changes_requested" }

      assert_equal 1, request_changes_workflows.length
      assert_equal [MemexProjectItem::PULL_REQUEST_TYPE], request_changes_workflows.first.content_types
      assert_equal status_options_by_name["Review in progress"][:id], request_changes_workflows.first.actions.first.arguments["fieldOptionId"]
    end

    test "successfully migrates approved workflows" do
      memex = assert_nothing_raised { MemexProject::Migrator.migrate!(@project_migration.id) }
      memex.reload

      status_options_by_name = memex.status_column.settings_options.index_by { |o| o[:name] }

      approved_workflows = memex.workflows.find_all { |w| w.trigger_type == "review_approved" }

      assert_equal 1, approved_workflows.length
      assert_equal [MemexProjectItem::PULL_REQUEST_TYPE], approved_workflows.first.content_types
      assert_equal status_options_by_name["Reviewer approved"][:id], approved_workflows.first.actions.first.arguments["fieldOptionId"]
    end

    test "successfully migrates closed workflows" do
      memex = assert_nothing_raised { MemexProject::Migrator.migrate!(@project_migration.id) }
      memex.reload

      status_options_by_name = memex.status_column.settings_options.index_by { |o| o[:name] }

      closed_workflows = memex.workflows.find_all { |w| w.trigger_type == "closed" }

      assert_equal 1, closed_workflows.length
      assert_same_elements [MemexProjectItem::ISSUE_TYPE, MemexProjectItem::PULL_REQUEST_TYPE], closed_workflows.first.content_types
      assert_equal status_options_by_name["Done"][:id], closed_workflows.first.actions.first.arguments["fieldOptionId"]
    end

    test "successfully migrates merged workflows" do
      memex = assert_nothing_raised { MemexProject::Migrator.migrate!(@project_migration.id) }
      memex.reload

      status_options_by_name = memex.status_column.settings_options.index_by { |o| o[:name] }

      merged = memex.workflows.find_all { |w| w.trigger_type == "merged" }

      assert_equal 1, merged.length
      assert_equal [MemexProjectItem::PULL_REQUEST_TYPE], merged.first.content_types
      assert_equal status_options_by_name["Done"][:id], merged.first.actions.first.arguments["fieldOptionId"]
    end

    test "successfully updates the project migration state" do
      assert @project_migration.pending?

      memex = assert_nothing_raised { MemexProject::Migrator.migrate!(@project_migration.id) }
      memex.reload

      assert_equal memex.id, @project_migration.reload.target_memex_project_id
      assert @project_migration.completed?
    end

    context ".populate_items!" do
      test "successfully populates an issue card as an issue item" do
        org_project = create(:org_project, owner: @org, name: "Review Board", body: "Our team review board.", public: false)

        column = create(:project_column, project: org_project, name: "todooo")
        issue = create(:issue, repository: @repo)
        card = create(:project_card,
          column: column,
          content: issue,
          creator: @admin
        )

        project_migration = create(:project_migration, requester: @admin, project: org_project)
        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }

        assert_equal 1, memex.memex_project_items.size

        issue_item = memex.memex_project_items.first
        assert_equal "Issue", issue_item.content_type
        assert_equal card.content_id, issue_item.content_id
      end

      test "successfully populates draft issue cards which have the same URL reference" do
        org_project = create(:org_project, owner: @org, name: "Review Board", body: "Our team review board.", public: false)

        column = create(:project_column, project: org_project, name: "todooo")
        issue = create(:issue, repository: @repo, user: @admin)
        card = create(:project_card, column: column, note: issue.url, creator: @admin)
        card = create(:project_card, column: column, note: issue.url, creator: @admin)

        memex_for_migration = create(:memex_project, owner: @admin)
        project_migration = create(:project_migration, requester: @admin, project: org_project, memex_project: memex_for_migration)
        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }

        assert_equal 2, memex.memex_project_items.size
        assert_equal issue.url, memex.memex_project_items.first.content.title
        assert_equal issue.url, memex.memex_project_items.second.content.title
      end

      test "successfully populates a pull request card as a pull request item" do
        org_project = create(:org_project, owner: @org, name: "Review Board", body: "Our team review board.", public: false)

        column = create(:project_column, project: org_project, name: "todooo")

        card = create(:project_card,
          column: column,
          content: @opened_pr,
          creator: @admin
        )

        project_migration = create(:project_migration, requester: @admin, project: org_project)
        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }

        assert_equal 1, memex.memex_project_items.size

        pull_request_item = memex.memex_project_items.first
        assert_equal "PullRequest", pull_request_item.content_type
        assert_equal card.content_id, pull_request_item.content_id
      end

      test "succesfully populates a card with a note as a draft issue item" do
        org_project = create(:org_project, owner: @org, name: "Review Board", body: "Our team review board.", public: false)
        column = create(:project_column, project: org_project)
        create(:project_card, note: "a hobgoblin thought", column: column)

        project_migration = create(:project_migration, requester: @admin, project: org_project)
        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }

        assert_equal 1, memex.memex_project_items.size

        draft_item = memex.memex_project_items.first
        assert_equal "DraftIssue", draft_item.content_type
        assert_equal "a hobgoblin thought", draft_item.content.title
      end

      test "populates title and body of a draft issue" do
        kanban_column_names = ["To do", "In progress", "Review in progress", "Reviewer approved", "Done"]
        org_project = create(:org_project, owner: @org, name: "Review Board", body: "Our team review board.", public: false)
        org_project.apply_template(ProjectTemplate::AutomatedReviewsKanban.new)

        number_cards = org_project.cards.size
        first_card = org_project.cards.first
        assert_equal kanban_column_names, org_project.columns.map(&:name)

        project_migration = create(:project_migration, requester: @admin, project: org_project)
        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }

        assert_equal number_cards, memex.memex_project_items.size

        draft_item = memex.memex_project_items.first
        assert_equal ":sparkles: **Welcome to GitHub projects** :sparkles:",  draft_item.content.title
        assert_equal ":sparkles: **Welcome to GitHub projects** :sparkles:\nWe're so excited that you've decided to create a new project! Now that you're here, let's make sure you know how to get the most out of GitHub projects.\n- [x] Create a new project\n- [x] Give your project a name\n- [ ] Press the <kbd>?</kbd> key to see available keyboard shortcuts\n- [ ] Add a new column\n- [ ] Drag and drop this card to the new column\n- [ ] Search for and add issues or PRs to your project\n- [ ] Manage automation on columns\n- [ ] [Archive a card](https://docs.github.com/articles/archiving-cards-on-a-project-board/) or archive all cards in a column\n", draft_item.content.body
      end

      test "maintains order of cards within a column" do
        kanban_column_names = ["To do", "In progress", "Review in progress", "Reviewer approved", "Done"]
        org_project = create(:org_project, owner: @org, name: "Review Board", body: "Our team review board.", public: false)
        org_project.apply_template(ProjectTemplate::AutomatedReviewsKanban.new)
        assert_equal kanban_column_names, org_project.columns.map(&:name)
        assert_equal [":sparkles: **Welcome to GitHub projects** :sparkles:", "**Cards**", "**Automation**"], org_project.columns.first.cards.not_archived.by_priority.map { |card| card.note.slice(0, card.note.index("\n")) }

        project_migration = create(:project_migration, requester: @admin, project: org_project)
        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }

        assert_equal [":sparkles: **Welcome to GitHub projects** :sparkles:", "**Cards**", "**Automation**"], memex.prioritized_scope(:memex_project_items).map { |item| item.content.title }
      end

      test "successfully ports a card in column named with trailing whitespace" do
        org_project = create(:org_project, owner: @org, name: "Review Board", body: "Our team review board.", public: false)

        column = create(:project_column, project: org_project, name: "To do      ")
        issue = create(:issue, repository: @repo)
        card = create(:project_card,
          column: column,
          content: issue,
          creator: @admin
        )

        project_migration = create(:project_migration, requester: @admin, project: org_project)
        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }

        assert_equal 1, memex.memex_project_items.size

        issue_item = memex.memex_project_items.first
        assert_equal "Issue", issue_item.content_type
        assert_equal card.content_id, issue_item.content_id
      end

      test "preserves sort order when there are fewer cards than the limit" do
        org_project = create(:org_project, owner: @org, name: "Review Board")
        column = create(:project_column, project: org_project, name: "TODO")

        create(:project_card, column: column, content: @closed_pr, creator: @admin, priority: 1)
        create(:project_card, column: column, content: @opened_issue, creator: @admin, priority: 2)
        create(:project_card, column: column, content: @closed_issue, creator: @admin, priority: 3)
        create(:project_card, column: column, content: @opened_pr, creator: @admin, priority: 4)
        create(:project_card, column: column, content: @merged_pr, creator: @admin, priority: 5)

        project_migration = create(:project_migration, requester: @admin, project: org_project)
        memex = MemexProject::Migrator.migrate!(project_migration.id)
        memex.reload

        assert_equal [@merged_pr.id, @opened_pr.id, @closed_issue.id, @opened_issue.id, @closed_pr.id], memex.prioritized_scope(:memex_project_items).map { |item| item.content_id }
      end

      test "archives cards from archived repositories" do
        org_project = create(:org_project, owner: @org, name: "Review Board")
        column = create(:project_column, project: org_project, name: "TODO")

        repo_1 = create(:repository, owner: @org, from_example: :repository_test_simple)
        repo_2 = create(:repository, owner: @org, from_example: :repository_test_simple)

        repo_1_pr = create(:pull_request, :disable_disk_access, repository: repo_1, user: @admin)
        repo_1_issue = create(:issue, repository: repo_1, state: :closed)
        repo_2_pr = create(:pull_request, :disable_disk_access, repository: repo_2, user: @admin)
        repo_2_issue = create(:issue, repository: repo_2, state: :closed)

        repo_1.set_archived(synchronous: true)
        repo_2.set_archived(synchronous: true)

        # 4 cards that should all be archived
        create(:project_card, column: column, content: repo_1_pr, creator: @admin)
        create(:project_card, column: column, content: repo_1_issue, creator: @admin)
        create(:project_card, column: column, content: repo_2_pr, creator: @admin)
        create(:project_card, column: column, content: repo_2_issue, creator: @admin)

        # 1 non-archived card
        create(:project_card, column: column, content: @opened_pr, creator: @admin)

        project_migration = create(:project_migration, requester: @admin, project: org_project)
        expected_queries = {
          issues: 3,
          project_cards: 9,
          project_columns: 1,
          pull_requests: 2,
          repositories: TestEnv.test_all_features? ? 18 : 19 # Yikes, this is a lot of queries, but prefilling repositories association in build_items! removes an n+1
        }

        assert_query_count_per_table(expected_queries) do
          memex = MemexProject::Migrator.migrate!(project_migration.id)
          memex.reload

          archived, unarchived = memex.memex_project_items.partition { |item| item.archived? }
          assert_same_elements [repo_1_pr.id, repo_1_issue.id, repo_2_pr.id, repo_2_issue.id], archived.map { |item| item.content_id }
          assert_same_elements [@opened_pr.id], unarchived.map { |item| item.content_id }
        end
      end

      test "migrates archived cards" do
        org_project = create(:org_project, owner: @org, name: "Review Board")
        column = create(:project_column, project: org_project, name: "TODO")

        create(:project_card, column: column, content: @opened_issue, creator: @admin)

        create(:project_card, column: column, content: @closed_pr, creator: @admin, archived_at: 2.days.ago)
        create(:project_card, column: column, content: @closed_issue, creator: @admin, archived_at: 2.days.ago)
        create(:project_card, column: column, content: @opened_pr, creator: @admin, archived_at: 2.days.ago)
        create(:project_card, column: column, content: @merged_pr, creator: @admin, archived_at: 2.days.ago)

        project_migration = create(:project_migration, requester: @admin, project: org_project)
        memex = MemexProject::Migrator.migrate!(project_migration.id)
        memex.reload

        archived, unarchived = memex.memex_project_items.partition { |item| item.archived? }

        assert_equal @opened_issue.id, unarchived.first.content_id
        # we don't care much about the order of the archive since it's time-dependent
        assert_same_elements [@closed_pr.id, @closed_issue.id, @opened_pr.id, @merged_pr.id], archived.map { |item| item.content_id }
      end

      test "archives closed cards (regardless of source order) first when there are more than the limit" do
        MemexProjectItem.stub_const(:PER_PAGE_LIMIT, 2) do
          org_project = create(:org_project, owner: @org, name: "Review Board")
          column = create(:project_column, project: org_project, name: "TODO")

          create(:project_card, column: column, content: @opened_issue, creator: @admin, priority: 1)
          create(:project_card, column: column, content: @closed_pr, creator: @admin, priority: 2)
          create(:project_card, column: column, content: @closed_issue, creator: @admin, priority: 3)
          create(:project_card, column: column, content: @opened_pr, creator: @admin, priority: 4)
          create(:project_card, column: column, content: @merged_pr, creator: @admin, priority: 5)

          project_migration = create(:project_migration, requester: @admin, project: org_project)
          memex = MemexProject::Migrator.migrate!(project_migration.id)
          memex.reload

          archived, unarchived = memex.memex_project_items.partition { |item| item.archived? }
          assert_same_elements [@opened_issue.id, @opened_pr.id], unarchived.map { |item| item.content_id }
          assert_same_elements [@closed_pr.id, @closed_issue.id, @merged_pr.id], archived.map { |item| item.content_id }
        end
      end

      test "discards extra cards without erroring when the archive limit is reached" do
        MemexProject.any_instance.stubs(:archived_items_limit).returns(2)
        org_project = create(:org_project, owner: @org, name: "Review Board")
        column = create(:project_column, project: org_project, name: "TODO")

        create(:project_card, column: column, content: @closed_pr, creator: @admin, archived_at: 2.days.ago)
        create(:project_card, column: column, content: @closed_issue, creator: @admin, archived_at: 2.days.ago)
        create(:project_card, column: column, content: @opened_pr, creator: @admin, archived_at: 2.days.ago)
        create(:project_card, column: column, content: @merged_pr, creator: @admin, archived_at: 2.days.ago)

        project_migration = create(:project_migration, requester: @admin, project: org_project)
        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }
        memex.reload

        assert_equal memex.memex_project_items.to_a.count { |item| item.archived? }, 2
      end
    end

    context "permissions" do
      test "migrator creates a memex project with the correct user and team permissions for an org owned project" do
        org_project = create(:org_project, owner: @org, name: "Review Board", body: "Our team review board.", public: false)

        # Set up users
        admin_user = create(:verified_user)
        write_user = create(:verified_user)
        read_user = create(:verified_user)

        # Set up teams
        admin_team = create(:team, organization: @org)
        write_team = create(:team, organization: @org)
        read_team = create(:team, organization: @org)

        # Set up users for the teams
        admin_team_user = create(:verified_user)
        write_team_user = create(:verified_user)
        read_team_user = create(:verified_user)

        # Disable base write permissions for any org members
        org_project.update_org_permission(:read)

        # Add team users to teams
        admin_team.add_member(admin_team_user)
        write_team.add_member(write_team_user)
        read_team.add_member(read_team_user)

        # Set up permissions for the classic project
        org_project.update_user_permission(admin_user, :admin)
        org_project.update_user_permission(write_user, :write)
        org_project.update_user_permission(read_user, :read)

        org_project.update_team_permission(admin_team, :admin)
        org_project.update_team_permission(write_team, :write)
        org_project.update_team_permission(read_team, :read)

        # Migrate the classic project to a memex project
        project_migration = create(:project_migration, requester: @admin, project: org_project)
        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }

        # Assert users have correct permissions
        assert_equal true, memex.viewer_is_admin?(admin_user)
        assert_equal true, memex.viewer_can_write?(admin_user)
        assert_equal true, memex.viewer_can_read?(admin_user)

        assert_equal false, memex.viewer_is_admin?(write_user)
        assert_equal true, memex.viewer_can_write?(write_user)
        assert_equal true, memex.viewer_can_read?(write_user)

        assert_equal false, memex.viewer_is_admin?(read_user)
        assert_equal false, memex.viewer_can_write?(read_user)
        assert_equal true, memex.viewer_can_read?(read_user)

        # Assert users on the teams have correct permissions via their team
        assert_equal true, memex.viewer_is_admin?(admin_team_user)
        assert_equal true, memex.viewer_can_write?(admin_team_user)
        assert_equal true, memex.viewer_can_read?(admin_team_user)

        assert_equal false, memex.viewer_is_admin?(write_team_user)
        assert_equal true, memex.viewer_can_write?(write_team_user)
        assert_equal true, memex.viewer_can_read?(write_team_user)

        assert_equal false, memex.viewer_is_admin?(read_team_user)
        assert_equal false, memex.viewer_can_write?(read_team_user)
        assert_equal true, memex.viewer_can_read?(read_team_user)
      end

      test "migrator creates a memex project with the correct user permissions for a repository owned project" do
        admin_user = create(:verified_user)
        org = create(:organization, admin: admin_user)
        private_repo = create(:private_repository, owner: org)
        private_repo_project = create(:project, owner: private_repo, name: "Review Board", body: "Our team review board.", public: false)

        # Set up users
        write_user = create(:verified_user)
        read_user = create(:verified_user)

        private_repo.add_member(write_user)
        org.add_member(read_user)

        # Set up permissions for the classic project
        private_repo_project.update_user_permission(write_user, :write)
        private_repo_project.update_user_permission(read_user, :read)

        # Migrate the classic project to a memex project
        project_migration = create(:project_migration, requester: admin_user, project: private_repo_project)
        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }

        # Assert users have correct permissions
        assert_equal true, memex.viewer_is_admin?(admin_user)
        assert_equal true, memex.viewer_can_write?(admin_user)
        assert_equal true, memex.viewer_can_read?(admin_user)

        assert_equal false, memex.viewer_is_admin?(write_user)
        assert_equal true, memex.viewer_can_write?(write_user)
        assert_equal true, memex.viewer_can_read?(write_user)

        assert_equal false, memex.viewer_is_admin?(read_user)
        assert_equal false, memex.viewer_can_write?(read_user)
        assert_equal true, memex.viewer_can_read?(read_user)
      end

      test "migrator creates a memex project with the correct organization permissions" do
        org_project = create(:org_project, owner: @org, name: "Review Board", body: "Our team review board.", public: false)

        project_migration = create(:project_migration, requester: @admin, project: org_project)
        org_project.update_org_permission(:admin)
        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }
        assert_equal "project_admin", memex.organization_wide_role

        project_migration = create(:project_migration, requester: @admin, project: org_project)
        org_project.update_org_permission(:write)
        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }
        assert_equal "project_writer", memex.organization_wide_role

        project_migration = create(:project_migration, requester: @admin, project: org_project)
        org_project.update_org_permission(:read)
        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }
        assert_equal "project_reader", memex.organization_wide_role

        project_migration = create(:project_migration, requester: @admin, project: org_project)
        org_project.update_org_permission(nil)
        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }
        assert_equal "none", memex.organization_wide_role
      end

      test "does not enable mwl even for an eligible project" do
        MemexProject.stubs(:create_with_mwl_enabled?).returns(true)
        GitHub.flipper[:memex_table_without_limits].disable

        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(@project_migration.id) }

        refute memex.feature_enabled?(:memex_table_without_limits)
      end

      # regression test for https://github.com/github/memex/issues/18477
      test "migrates collaborators even when project has a 'none' base role" do
        creator = create(:verified_user, login: "creator")
        @org.add_member(creator)
        org_project = create(:org_project, owner: @org, name: "Review Board", body: "Our team review board.", public: false, creator: creator)

        # Set up users
        admin_user = create(:verified_user, login: "admin-user")
        write_user = create(:verified_user, login: "write-user")
        read_user = create(:verified_user, login: "read-user")
        random_org_member = create(:verified_user, login: "random-org-member")
        @org.add_member(random_org_member)

        # Disable base write permissions for any org members
        org_project.update_org_permission(nil)

        # Set up permissions for the classic project
        org_project.update_user_permission(admin_user, :admin)
        org_project.update_user_permission(write_user, :write)
        org_project.update_user_permission(read_user, :read)

        # Migrate the classic project to a memex project
        project_migration = create(:project_migration, requester: @admin, project: org_project)
        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }

        # Assert that the project has the right collaborators
        expected_collaborators = %w(admin-user write-user read-user creator)
        assert_equal expected_collaborators.sort, memex.collaborators(creator).map { |c| c.actor[:login] }.sort

        # Assert users have correct permissions
        assert_equal true, memex.viewer_is_admin?(creator)
        assert_equal true, memex.viewer_can_write?(creator)
        assert_equal true, memex.viewer_can_read?(creator)

        assert_equal true, memex.viewer_is_admin?(admin_user)
        assert_equal true, memex.viewer_can_write?(admin_user)
        assert_equal true, memex.viewer_can_read?(admin_user)

        assert_equal false, memex.viewer_is_admin?(write_user)
        assert_equal true, memex.viewer_can_write?(write_user)
        assert_equal true, memex.viewer_can_read?(write_user)

        assert_equal false, memex.viewer_is_admin?(read_user)
        assert_equal false, memex.viewer_can_write?(read_user)
        assert_equal true, memex.viewer_can_read?(read_user)

        assert_equal false, memex.viewer_is_admin?(random_org_member)
        assert_equal false, memex.viewer_can_write?(random_org_member)
        assert_equal false, memex.viewer_can_read?(random_org_member)
      end

      test "migrates collaborators for user project" do
        creator = create(:verified_user, login: "creator")
        user_project = create(:project, owner: creator, name: "Review Board", body: "Our team review board.", public: false, creator: creator)

        # Set up users
        admin_user = create(:verified_user, login: "admin-user")
        write_user = create(:verified_user, login: "write-user")
        read_user = create(:verified_user, login: "read-user")
        random_user = create(:verified_user, login: "random-user")

        # Set up permissions for the classic project
        user_project.update_user_permission(admin_user, :admin)
        user_project.update_user_permission(write_user, :write)
        user_project.update_user_permission(read_user, :read)

        # Migrate the classic project to a memex project
        project_migration = create(:project_migration, requester: creator, project: user_project)
        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }

        # Assert that the project has the right collaborators
        expected_collaborators = %w(admin-user write-user read-user)
        assert_equal expected_collaborators.sort, memex.collaborators(creator).map { |c| c.actor[:login] }.sort

        # Assert users have correct permissions
        assert_equal true, memex.viewer_is_admin?(creator)
        assert_equal true, memex.viewer_can_write?(creator)
        assert_equal true, memex.viewer_can_read?(creator)

        assert_equal true, memex.viewer_is_admin?(admin_user)
        assert_equal true, memex.viewer_can_write?(admin_user)
        assert_equal true, memex.viewer_can_read?(admin_user)

        assert_equal false, memex.viewer_is_admin?(write_user)
        assert_equal true, memex.viewer_can_write?(write_user)
        assert_equal true, memex.viewer_can_read?(write_user)

        assert_equal false, memex.viewer_is_admin?(read_user)
        assert_equal false, memex.viewer_can_write?(read_user)
        assert_equal true, memex.viewer_can_read?(read_user)

        assert_equal false, memex.viewer_is_admin?(random_user)
        assert_equal false, memex.viewer_can_write?(random_user)
        assert_equal false, memex.viewer_can_read?(random_user)
      end

      test "does not add creator as collaborator if creator is not part of org" do
        creator = create(:verified_user, login: "creator")
        org_project = create(:org_project, owner: @org, name: "Review Board", body: "Our team review board.", public: false, creator: creator)

        # Migrate the classic project to a memex project
        project_migration = create(:project_migration, requester: @admin, project: org_project)
        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }

        assert_equal [], memex.collaborators(creator)
        assert_equal false, memex.viewer_is_admin?(creator)
        assert_equal false, memex.viewer_can_write?(creator)
        assert_equal false, memex.viewer_can_read?(creator)
      end

      # regression test for https://github.com/github/memex/issues/18471
      test "sets 'none' base role on memex project if classic project owned by a repository has default repo permissions of none" do
        creator = create(:verified_user)
        org = create(:organization, admin: create(:verified_user))
        org.add_member(creator)
        perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
          org.update_default_repository_permission(:none, actor: creator)
        end

        assert_equal "project_writer", org.projects_base_role

        private_repo = create(:private_repository, owner: org)
        assert_equal :none, private_repo.organization&.default_repository_permission
        # Add the creator as an admin, even though they were a writer. This is because repository projects are adminable
        # by those who can write to the projects.
        private_repo.add_member(creator, action: :admin)

        private_repo_project = create(:project, owner: private_repo, name: "Review Board", body: "Our team review board.", public: false, creator: creator)

        # Set up users
        random_org_member = create(:verified_user, login: "random-org-member")
        org.add_member(random_org_member)

        # Migrate the classic project to a memex project
        project_migration = create(:project_migration, requester: creator, project: private_repo_project)
        memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }

        assert_equal "none", memex.organization_wide_role
        assert_equal false, memex.viewer_can_read?(random_org_member)
        assert_equal true, memex.viewer_can_read?(creator)
        assert_equal true, memex.viewer_can_write?(creator)
        assert_equal true, memex.viewer_is_admin?(creator)
      end
    end

    test "does not make excessive number of queries" do
      GitHub.flipper.enable(:projects_classic_migration_disable_webhooks)
      GitHub.flipper[:tasklist_block].enable(@org)
      kanban_column_names = ["To do", "In progress", "Review in progress", "Reviewer approved", "Done"]
      org_project = create(:org_project, owner: @org, name: "Review Board", body: "Our team review board.", public: false)
      org_project.apply_template(ProjectTemplate::AutomatedReviewsKanban.new)
      assert_equal kanban_column_names, org_project.columns.map(&:name)

      todo = org_project.columns.find_by(name: "To do")
      in_progress = org_project.columns.find_by(name: "In progress")
      create(:project_card, column: todo, content: @opened_issue, creator: @admin, priority: 1)
      create(:project_card, column: in_progress, content: @closed_pr, creator: @admin, priority: 2)
      create(:project_card, column: todo, content: @closed_issue, creator: @admin, priority: 3)
      create(:project_card, column: todo, content: @opened_pr, creator: @admin, priority: 4)
      create(:project_card, column: in_progress, content: @merged_pr, creator: @admin, priority: 5)

      create(:project_card, note: "a hobgoblin thought", column: todo)

      project_migration = create(:project_migration, requester: @admin, project: org_project)
      assert_nothing_raised do
        assert_query_count_per_table({
          memex_projects: 3, # Initial count was 16 as of 2024-07-19 (for reference)
          memex_project_items: 22, # Initial count was 124 as of 2024-07-19 (for reference)
          memex_project_views: 10, # Initial count was 12 as of 2024-07-19 (for reference)
          memex_project_columns: 19, # Initial count was 71 as of 2024-07-19 (for reference)
          memex_project_column_values: 18, # Initial count was 18 as of 2024-07-19 (for reference)
          memex_project_workflows: 15, # Initial count was 22 as of 2024-07-19 (for reference)
          memex_project_workflow_actions: 7, # Initial count was 7 as of 2024-07-19 (for reference)
          memex_project_visits: 0, # Initial count was 9 as of 2024-07-19 (for reference)
          project_migrations: 17, # Initial count was 17 as of 2024-07-19 (for reference)
          project_cards: 9, # Initial count was 9 as of 2024-07-19 (for reference)
          project_columns: 1, # Initial count was 1 as of 2024-07-19 (for reference)
          draft_issues: 4, # Initial count was 4 as of 2024-07-19 (for reference)
          abilities: 2, # Initial count was 2 as of 2024-07-19 (for reference)
          sequences: 29, # Initial count was 29 as of 2024-07-19 (for reference)
          issues: 3, # Initial count was 10 as of 2024-07-19 (for reference)
          pull_requests: 2, # Initial count was 2 as of 2024-07-19 (for reference)
          configuration_entries: 3, # Initial count was 3 as of 2024-07-19 (for reference)
          roles: 1, # Initial count was 1 as of 2024-07-19 (for reference)
          users: 21, # Initial count was 63 as of 2024-07-19 (for reference)
          businesses: 3, # Initial count was 13 as of 2024-07-19 (for reference)
          business_organization_memberships: 4, # Initial count was 15 as of 2024-07-19 (for reference)
        }) do
          # This was previously 19 webhook deliver jobs
          assert_enqueued_jobs 0, only: DeliverHookEventJob do
            assert_enqueued_jobs 0, only: SyncMemexProjectItemByIdToIssuesGraphJob do
              assert_enqueued_jobs 1, only: SyncMemexProjectHierarchyJob do
                MemexProject::Migrator.migrate!(project_migration.id)
              end
            end
          end
        end
      end
    end
  end
end
