# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectLinkTest < GitHub::TestCase
  context "validations" do
    test "requires source association" do
      link = MemexProjectLink.new

      refute_predicate link, :valid?
      assert link.errors.of_kind?(:source, :blank), "must exist"
    end

    test "requires target memex_project" do
      link = MemexProjectLink.new

      refute_predicate link, :valid?
      assert link.errors.of_kind?(:memex_project, :blank), "must exist"
    end

    test "requires same owner for repository links" do
      memex = create(:memex_project)
      repo = create(:repository)
      link = build(:memex_project_link, source: repo, memex_project: memex)

      refute_predicate link, :valid?
      refute_equal repo.owner, memex.owner
      assert_includes link.errors[:base], "The selected project and repository must have the same owner."
    end

    test "requires same owner for organization links" do
      organization = create(:organization)
      memex = create(:memex_project)
      link = build(:memex_project_link, source_type: "Organization", source_id: organization.id, memex_project: memex)

      refute_predicate link, :valid?
      refute_equal organization, memex.owner
      assert_includes link.errors[:base], "The selected project template must have the same owner."
    end

    test "requires uniqueness for a source-project pair" do
      link = build(:memex_project_link)
      assert link.save

      another_link = build(:memex_project_link, source: link.source, memex_project: link.memex_project)
      refute_predicate another_link, :valid?
      assert another_link.errors.of_kind?(:memex_project, :taken), "must be unique"
    end

    test "creates a valid link for a project and a repo, org owned" do
      memex = create(:memex_project)
      repo = create(:repository, owner: memex.owner)
      link = create(:memex_project_link, source: repo, memex_project: memex)

      assert_equal "Repository", link.source_type
    end

    test "creates a valid link for a project and a repo, user owned" do
      user = create(:user)
      memex = create(:memex_project, owner: user)
      repo = create(:repository, owner: user)
      link = create(:memex_project_link, source: repo, memex_project: memex)

      assert_equal "Repository", link.source_type
    end

    test "requires MemexTemplate for Organization links" do
      organization = create(:organization)
      memex_project = create(:memex_project, owner: organization)
      memex_project_link = build(:memex_project_link, source_type: "Organization", source_id: organization.id, memex_project: memex_project)

      assert_nil memex_project.memex_template
      refute_predicate memex_project_link, :valid?
      assert memex_project_link.errors.of_kind?(:memex_project, :expected_memex_template)
    end

    test "requires an active MemexTemplate for Organization links" do
      organization = create(:organization)
      memex_project = create(:memex_project, owner: organization)
      memex_template = create(:memex_template, memex_project: memex_project, active: false)
      memex_project_link = build(:memex_project_link, source_type: "Organization", source_id: organization.id, memex_project: memex_project)

      refute_predicate memex_project.memex_template, :active?
      refute_predicate memex_project_link, :valid?
      assert memex_project_link.errors.of_kind?(:memex_project, :expected_memex_template)
    end

    test "cannot exceed limit of recommended MemexTemplates for Organization links" do
      organization = create(:organization)
      MemexTemplate.stub_const(:MAX_ORGANIZATION_RECOMMENDED_TEMPLATES, 1) do
        memex_project = create(:memex_project, owner: organization)
        memex_template = create(:memex_template, memex_project: memex_project)
        memex_project_link = create(:memex_project_link, source_type: "Organization", source_id: organization.id, memex_project: memex_project)
        limited_memex_project = create(:memex_project, owner: organization)
        limited_memex_template = create(:memex_template, memex_project: limited_memex_project)
        limited_memex_project_link = build(:memex_project_link, source_type: "Organization", source_id: organization.id, memex_project: limited_memex_project)

        refute_predicate limited_memex_project_link, :valid?
        assert limited_memex_project_link.errors.of_kind?(:source, :exceeded_memex_template_link_limit)
      end
    end

    test "cannot exceed limit of curated MemexProject links for source" do
      organization = create(:organization)
      MemexProject.stub_const(:MAX_REPO_CURATED_PROJECTS, 1) do
        memex_project = create(:memex_project, owner: organization)
        repository = create(:repository, owner: organization)
        memex_project_link = create(:memex_project_link, source: repository, memex_project: memex_project)
        limited_memex_project = create(:memex_project, owner: organization)
        limited_memex_project_link = build(:memex_project_link, source: repository, memex_project: limited_memex_project)

        refute_predicate limited_memex_project_link, :valid?
        assert limited_memex_project_link.errors.of_kind?(:source, :exceeded_memex_project_link_limit)
      end
    end
  end

  context "accessible properties" do
    test "memexes are accessible on the repo object" do
      memex = create(:memex_project)
      repo = create(:repository, owner: memex.owner)
      link = create(:memex_project_link, source: repo, memex_project: memex)

      assert_equal repo.memex_projects, [memex]
    end
  end
end
