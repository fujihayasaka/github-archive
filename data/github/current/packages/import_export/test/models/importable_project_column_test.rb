# typed: true
# frozen_string_literal: true

require "test_helper"

class ImportableProjectColumnTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    repo = create(:importable_repository, owner: @org)
    @repo = Repository.find_by(id: repo.id)
    @project = create(:importable_project, owner: @repo)
    @mannequin = create(:mannequin, owner: @org)
  end

  context "#new" do
    test "should create a project column" do
      created_at = Time.now - 7.days

      project_column = ImportableProjectColumn.new(
        project: @project,
        name: "New project column",
        created_at: created_at
      )

      assert project_column.save
      assert_equal @project.id, project_column.project_id
      assert_equal "New project column", project_column.name
      assert_equal created_at.to_i, project_column.created_at.to_i
    end

    context "skipped callbacks" do
      context "#notify_project" do
        test "is skipped within an import context" do
          ImportableProjectColumn.any_instance.expects(:notify_project).never
          create(:importable_project_column)
        end

        test "is not skipped outside an import context" do
          ProjectColumn.any_instance.expects(:notify_project).once
          create(:project_column)
        end
      end

      context "#actor_can_modify_projects" do
        test "is skipped within an import context" do
          ImportableProjectColumn.any_instance.expects(:actor_can_modify_projects).never
          create(:importable_project_column)
        end

        test "is not skipped outside an import context" do
          ProjectColumn.any_instance.expects(:actor_can_modify_projects).once
          create(:project_column)
        end
      end
    end
  end
end
