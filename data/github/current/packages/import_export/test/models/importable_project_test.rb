# typed: true
# frozen_string_literal: true

require "test_helper"

class ImportableProjectTest < GitHub::TestCase
  fixtures do
    repo = create(:importable_repository)
    @repo = Repository.find_by(id: repo.id)
    @org = create(:organization)
    @mannequin = create(:mannequin, owner: @org)
  end

  context "#build_project" do
    test "should create an open project" do
      created_at = Time.now - 7.days
      project = ImportableProject.new(
        owner: @repo,
        creator:  @repo.owner,
        name: "New project title",
        body: "Body of the project",
        number: 1,
        created_at: created_at,
        updated_at: created_at
      )

      assert project.save
      assert_equal @repo.id, project.owner_id
      assert_equal "Repository", project.owner_type
      assert_equal "New project title", project.name
      assert_equal "Body of the project", project.body
      assert_equal 1, project.number
      assert_equal @repo.owner.id, project.creator_id
      assert_equal created_at.to_i, project.created_at.to_i
      assert_equal created_at.to_i, project.updated_at.to_i
      refute project.closed?
    end

    test "should create a closed project" do
      created_at = Time.now - 7.days
      closed_at = created_at + 5.minutes
      project = ImportableProject.new(
        owner: @repo,
        creator:  @repo.owner,
        name: "New project title",
        body: "Body of the project",
        number: 1,
        created_at: created_at,
        updated_at: created_at,
        closed_at: created_at + 5.minutes
      )

      assert project.save
      assert_equal @repo.id, project.owner_id
      assert_equal "Repository", project.owner_type
      assert_equal "New project title", project.name
      assert_equal "Body of the project", project.body
      assert_equal 1, project.number
      assert_equal @repo.owner.id, project.creator_id
      assert_equal created_at.to_i, project.created_at.to_i
      assert_equal created_at.to_i, project.updated_at.to_i
      assert_equal closed_at.to_i, project.closed_at.to_i
      assert project.closed?
    end

    context "when creator is a mannequin" do
      test "should create a project" do
        created_at = Time.now - 7.days
        project = ImportableProject.new(
          owner: @repo,
          creator:  @mannequin,
          name: "New project title",
          body: "Body of the project",
          number: 1,
          created_at: created_at,
          updated_at: created_at
        )

        assert project.save
        assert_equal "New project title", project.name
        assert_equal @repo.id, project.owner_id
        assert_equal "Repository", project.owner_type
        assert_equal "Body of the project", project.body
        assert_equal @mannequin.id, project.creator_id
        assert_equal 1, project.number
        assert_equal created_at.to_i, project.created_at.to_i
        assert_equal created_at.to_i, project.updated_at.to_i
        refute project.closed?
      end
    end
  end

  context "skipped callbacks" do
    context "#actor_can_modify_projects" do
      test "is skipped within an import context" do
        ImportableProject.any_instance.expects(:actor_can_modify_projects).never
        create(:importable_project)
      end

      test "is not skipped outside an import context" do
        Project.any_instance.expects(:actor_can_modify_projects).once
        create(:project)
      end
    end
  end

  context "sequencing" do
    test "should allow creating a project with a given number" do
      created_at = Time.now - 7.days
      project = ImportableProject.new(
        owner: @repo,
        creator:  @mannequin,
        name: "New project title",
        body: "Body of the project",
        number: 1234,
        created_at: created_at,
        updated_at: created_at
      )

      assert project.save
      assert_equal 1234, project.number
    end

    test "should continue sequencing properly after creating a new project without a number" do
      created_at = Time.now - 7.days
      first_project = ImportableProject.new(
        owner: @repo,
        creator:  @mannequin,
        name: "New project title",
        body: "Body of the project",
        number: 1234,
        created_at: created_at,
        updated_at: created_at
      )

      assert first_project.save

      second_project = Project.new(
        owner: @repo,
        creator:  @mannequin,
        name: "Second project title",
        body: "Body of the project",
        created_at: created_at,
      )

      assert second_project.save
      assert_equal 1235, second_project.number
    end
  end
end
