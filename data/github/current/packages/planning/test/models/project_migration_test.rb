# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectMigrationTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "org-owner")
    @org = create(:organization, admin: @owner)
    @member = create(:user, login: "org-member")
    @org.add_member(@member)

    @project = create(:project, owner: @org)

    @org_memex_project = create(:memex_project, owner: @org)
    @user_memex_project = create(:memex_project, owner: @owner)

    # Apps::Privileged::MemexAutomation.bot is used as the creator in the migration, so we must create it here
    make_trusted_oauth_apps_owner
    Apps::Privileged::MemexAutomation.seed_database!
    Apps::Privileged::MemexAutomation.reload!
    @bot = Apps::Privileged::MemexAutomation.bot
  end

  context "validations" do
    test "requires a valid requester on create" do
      project_migration = build(:project_migration, requester: nil)

      refute project_migration.save
      assert_includes project_migration.errors.full_messages, "Requester can't be blank"
    end

    test "requires a classic project on create" do
      project_migration = build(:project_migration, requester: @member, project: nil)

      refute project_migration.save
      assert_includes project_migration.errors.full_messages, "Project can't be blank"
    end

    test "requires a memex project on update" do
      project_migration = create(:project_migration, requester: @member, project: @project)

      assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Memex project can't be blank") do
        project_migration.completed!
      end
    end

    test "creates a project migration for a classic project with pending status" do
      project_migration = build(:project_migration, requester: @member, project: @project)

      assert project_migration.save
      assert project_migration.pending?
    end

    test "allows a state transition when memex project exists" do
      project_migration = create(:project_migration, requester: @member, project: @project)
      project_migration.update!(memex_project: @org_memex_project, status: :completed)
      project_migration.reload

      assert_equal @org_memex_project.id, project_migration.target_memex_project_id
      assert project_migration.completed?
    end
  end

  context "state change" do
    test "successfully transitions to in_progress_project_details" do
      project_migration = create(:project_migration, requester: @member, project: @project)
      assert project_migration.pending?

      project_migration.update!(memex_project: @org_memex_project)

      project_migration.in_progress_project_details!

      assert_equal @org_memex_project.id, project_migration.target_memex_project_id
      assert project_migration.in_progress_project_details?
    end

    test "successfully transitions to in_progress_status_fields" do
      project_migration = create(:project_migration, requester: @member, project: @project)
      assert project_migration.pending?

      project_migration.update!(memex_project: @org_memex_project)

      project_migration.in_progress_status_fields!

      assert_equal @org_memex_project.id, project_migration.target_memex_project_id
      assert project_migration.in_progress_status_fields?
    end

    test "successfully transitions to in_progress_default_view" do
      project_migration = create(:project_migration, requester: @member, project: @project)
      assert project_migration.pending?


      project_migration.update!(memex_project: @org_memex_project)

      project_migration.in_progress_default_view!

      assert_equal @org_memex_project.id, project_migration.target_memex_project_id
      assert project_migration.in_progress_default_view?
    end

    test "successfully transitions to in_progress_permissions" do
      project_migration = create(:project_migration, requester: @member, project: @project)
      assert project_migration.pending?

      project_migration.update!(memex_project: @org_memex_project)

      project_migration.in_progress_permissions!

      assert_equal @org_memex_project.id, project_migration.target_memex_project_id
      assert project_migration.in_progress_permissions?
    end

    test "successfully transitions to in_progress_items" do
      project_migration = create(:project_migration, requester: @member, project: @project)
      assert project_migration.pending?

      project_migration.update!(memex_project: @org_memex_project)

      project_migration.in_progress_items!

      assert_equal @org_memex_project.id, project_migration.target_memex_project_id
      assert project_migration.in_progress_items?
    end

    test "successfully transitions to in_progress_workflows" do
      project_migration = create(:project_migration, requester: @member, project: @project)
      assert project_migration.pending?

      project_migration.update!(memex_project: @org_memex_project)

      project_migration.in_progress_workflows!

      assert_equal @org_memex_project.id, project_migration.target_memex_project_id
      assert project_migration.in_progress_workflows?
    end

    test "successfully transitions to completed" do
      project_migration = create(:project_migration, requester: @member, project: @project)
      assert project_migration.pending?

      project_migration.update!(memex_project: @org_memex_project)

      project_migration.completed!

      assert_equal @org_memex_project.id, project_migration.target_memex_project_id
      assert project_migration.completed?
    end

    test "counts as completed when completion_acknowledged" do
      project_migration = create(:project_migration, requester: @member, project: @project)
      assert project_migration.pending?

      project_migration.update!(memex_project: @org_memex_project)

      project_migration.completion_acknowledged!

      assert_equal @org_memex_project.id, project_migration.target_memex_project_id
      assert project_migration.completed?
      assert project_migration.completion_acknowledged?
    end

    test "status_payload reflects the migration status" do
      project_migration = build(:project_migration, requester: @owner, project: @project)

      project_migration.save!

      assert_equal project_migration.status_payload, { status: "PENDING", message: "Migrating to Projects" }

      project_migration.update!(memex_project: @user_memex_project)

      project_migration.in_progress_project_details!

      assert_equal project_migration.status_payload, { status: "IN_PROGRESS_PROJECT_DETAILS", message: "Migrating to Projects" }

      project_migration.in_progress_status_fields!

      assert_equal project_migration.status_payload, { status: "IN_PROGRESS_STATUS_FIELDS", message: "Migrating to Projects" }

      project_migration.in_progress_default_view!

      assert_equal project_migration.status_payload, { status: "IN_PROGRESS_DEFAULT_VIEW", message: "Migrating to Projects" }

      project_migration.in_progress_permissions!

      assert_equal project_migration.status_payload, { status: "IN_PROGRESS_PERMISSIONS", message: "Migrating to Projects" }

      project_migration.in_progress_items!

      assert_equal project_migration.status_payload, { status: "IN_PROGRESS_ITEMS", message: "Migrating to Projects" }

      project_migration.in_progress_workflows!

      assert_equal project_migration.status_payload, { status: "IN_PROGRESS_WORKFLOWS", message: "Migrating to Projects" }

      project_migration.completed!

      assert_equal project_migration.status_payload, { status: "COMPLETED", message: "Migration complete!" }
    end

    test "is_automated returns correct value based on requester" do
      project_migration_user = create(:project_migration, requester: @member, project: @project)
      project_migration_bot = create(:project_migration, requester: @bot, project: @project)

      assert project_migration_bot.is_automated
      refute project_migration_user.is_automated
    end
  end
end
