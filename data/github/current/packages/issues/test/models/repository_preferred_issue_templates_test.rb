# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryPreferredIssueTemplatesTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @github_org = create(:organization, login: "github")
    @org_repo = create(:repository, owner: @org)
    @github_dot_github_repo = create(:repository, owner: @github_org, name: ".github")
    @dot_github_repo = create(:repository, owner: @org, name: ".github")
    @local_files_repo = create(:repository, owner: @org)
  end

  setup do
    example_repo :community_files, @dot_github_repo
    example_repo :community_files, @local_files_repo
  end

  test "returns local issue templates for repo with local templates" do
    templates = @local_files_repo.preferred_issue_templates.templates
    assert_equal 2, templates.count
    template = templates.shift
    assert_equal "bug_report.md", template.filename
    assert_equal "Bug report", template.name
    assert_equal @local_files_repo, template.repository
    template = templates.shift
    assert_equal "custom.md", template.filename
    assert_equal "Custom", template.name
    assert_equal @local_files_repo, template.repository
  end

  test "returns global issue templates for repo without local templates" do
    templates = @org_repo.preferred_issue_templates.templates
    assert_equal 2, templates.count
    template = templates.shift
    assert_equal "bug_report.md", template.filename
    assert_equal "Bug report", template.name
    assert_equal @dot_github_repo, template.repository
    template = templates.shift
    assert_equal "custom.md", template.filename
    assert_equal "Custom", template.name
    assert_equal @dot_github_repo, template.repository
  end

  context "return global supported issue templates without local templates" do

    context "when repo is private" do
      test "returns yaml|yml|md issue templates for private repo`" do
        private_github_repo = create(:private_repository, owner: @github_org)

        example_repo :simple, @github_dot_github_repo
        user = create(:user)
        @github_org.add_member(user)

        commit = @github_dot_github_repo.commits.create({ message: "Add templates", committer: user }) do |files|
          files.add ".github/ISSUE_TEMPLATE/feature.yaml", <<~YAML
          name: Feature
          description: It's a feature
          body:
          - type: input
            id: contact
            attributes:
              label: Contact Details
              description: How can we get in touch with you if we need more info?
              placeholder: ex. email@example.com
            validations:
              required: true
          YAML
          files.add ".github/ISSUE_TEMPLATE/bugs.md", <<~MARKDOWN
          ---
          name: Duplicate name
          about: It's a bug
          ---
          This is a bug.
          MARKDOWN
        end

        @github_dot_github_repo.refs["refs/heads/master"].update(commit, user)

        templates = private_github_repo.preferred_issue_templates.templates
        assert_equal 2, templates.count
      end
    end

    context "when repo is public" do
      test "returns yaml|yml|md issue templates for repo" do
        example_repo :simple, @dot_github_repo
        user = create(:user)
        @org.add_member(user)

        commit = @dot_github_repo.commits.create({ message: "Add templates", committer: user }) do |files|
          files.add ".github/ISSUE_TEMPLATE/feature.yaml", <<~YAML
          name: Feature
          description: It's a feature
          body:
          - type: input
            id: contact
            attributes:
              label: Contact Details
              description: How can we get in touch with you if we need more info?
              placeholder: ex. email@example.com
            validations:
              required: false
          YAML
          files.add ".github/ISSUE_TEMPLATE/bugs.md", <<~MARKDOWN
          ---
          name: Duplicate name
          about: It's a bug
          ---
          This is a bug.
          MARKDOWN
        end

        @dot_github_repo.refs["refs/heads/master"].update(commit, user)

        templates = @org_repo.preferred_issue_templates.templates
        assert_equal 2, templates.count
      end
    end
  end

  test "returns local templates for user owned repo" do
    user = create(:user)
    repo = create(:repository, owner: user, from_example: :community_files)
    # this repo should not serve any templates since it does not belong to an org
    user_dot_github = create(:repository, owner: user, name: ".github", from_example: :community_files)

    templates = repo.preferred_issue_templates.templates
    assert_equal 2, templates.count
    template = templates.shift
    assert_equal "bug_report.md", template.filename
    assert_equal "Bug report", template.name
    assert_equal repo, template.repository
    template = templates.shift
    assert_equal "custom.md", template.filename
    assert_equal "Custom", template.name
    assert_equal repo, template.repository
  end

  test "returns nil for repo with no templates at local level" do
    org = create(:organization)
    repo = create(:repository, owner: org, from_example: :simple)

    templates = repo.preferred_issue_templates.templates
    assert_equal 0, templates.count
  end
end
