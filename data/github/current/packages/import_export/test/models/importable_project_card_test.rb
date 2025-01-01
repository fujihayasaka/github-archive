# typed: true
# frozen_string_literal: true

require "test_helper"

class ImportableProjectCardTest < GitHub::TestCase
  fixtures do
    repo = create(:importable_repository)
    @repo = Repository.find_by(id: repo.id)
    @org = create(:organization)
    @mannequin = create(:mannequin, owner: @org)
    @project = create(:importable_project)
    @project_column = create(:importable_project_column, project: @project)
  end

  context "when creator is a mannequin" do
    test "should be persisted with the usual fields" do
      created_at = Time.now - 7.days
      importable_card = ImportableProjectCard.new(
        project: @project,
        column: @project_column,
        creator: @mannequin,
        created_at: created_at,
        note: "This is the text"
      )

      assert importable_card.save
      assert_equal @mannequin.id, importable_card.creator_id
      assert_equal created_at.to_i, importable_card.created_at.to_i
      assert_equal "This is the text", importable_card.note
    end
  end

  context "skipped callbacks" do
    context "#actor_can_modify_projects" do
      test "is skipped within an import context" do
        ImportableProjectCard.any_instance.expects(:actor_can_modify_projects).never
        create(:importable_project_card)
      end

      test "is not skipped outside an import context" do
        ProjectCard.any_instance.expects(:actor_can_modify_projects).once
        create(:project_card)
      end
    end
  end
end
