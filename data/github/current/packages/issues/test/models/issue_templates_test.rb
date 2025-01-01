# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueTemplatesTest < GitHub::TestCase
  fixtures do
    @repo   = create(:repository)
    @owner  = @repo.owner
  end

  setup do
    example_repo :simple, @repo
    commit = @repo.commits.create({ message: "Add templates", author: @repo.owner }) do |files|
      files.add ".github/ISSUE_TEMPLATE/bugs.md", <<~MARKDOWN
      ---
      name: Bug report
      about: It's a bug

      ---
      This is a bug.
      MARKDOWN

      files.add ".github/ISSUE_TEMPLATE/feature-request.md", <<~MARKDOWN
      ---
      name: Feature request
      about: It's a feature

      ---
      This is a feature request.
      MARKDOWN

      files.add ".github/ISSUE_TEMPLATE/bugs.yml", <<~YAML
      ---
      name: Structured bug report
      description: It's a feature
      body:
      - type: input
        attributes:
          label: "what is your bug"
      YAML

      files.add ".github/ISSUE_TEMPLATE/invalid_yaml_bugs.yml", <<~YAML
      ---
      name: Invalid structured bug report
      description: It's a feature
      body: [
      YAML
    end

    @repo.refs["refs/heads/master"].update(commit, @repo.owner)
  end

  test "can list issues and structured templates" do
    issue_templates = IssueTemplates.new(@repo)
    assert_equal 3, issue_templates.valid_templates.size

    bugs_template, structured_bugs_template, feature_request_template = issue_templates.valid_templates

    assert_equal "bugs.md", bugs_template.filename
    assert_equal "Bug report", bugs_template.name
    assert_equal @repo, bugs_template.repository

    assert_equal "bugs.yml", structured_bugs_template.filename
    assert_equal "Structured bug report", structured_bugs_template.name
    assert_equal @repo, structured_bugs_template.repository

    assert_equal "feature-request.md", feature_request_template.filename
    assert_equal "Feature request", feature_request_template.name
    assert_equal @repo, feature_request_template.repository
  end

  test "can filter templates" do
    issue_templates = IssueTemplates.new(@repo, nil, "bugs.yml")
    assert_equal 1, issue_templates.valid_templates.size

    bugs_template = issue_templates.valid_templates.first

    assert_equal "bugs.yml", bugs_template.filename
    assert_equal "Structured bug report", bugs_template.name
    assert_equal @repo, bugs_template.repository
  end

  test "includes structured templates" do
    issue_templates = IssueTemplates.new(@repo)
    assert_equal 3, issue_templates.valid_templates.size

    bugs_template, structured_bugs_template, feature_request_template = issue_templates.valid_templates

    assert_equal "bugs.md", bugs_template.filename
    assert_equal "Bug report", bugs_template.name
    assert_equal @repo, bugs_template.repository

    assert_equal "bugs.yml", structured_bugs_template.filename
    assert_equal "Structured bug report", structured_bugs_template.name
    assert_equal @repo, structured_bugs_template.repository

    assert_equal "feature-request.md", feature_request_template.filename
    assert_equal "Feature request", feature_request_template.name
    assert_equal @repo, feature_request_template.repository
  end

  test "legacy issue template in the .github/ folder has a name and about frontmatter by default" do
    commit = @repo.commits.create({ message: "Add templates", author: @repo.owner }) do |files|
      files.add ".github/issue-template.md", <<~MARKDOWN
      > This is a legacy issue template
      which comes with a default 'name' and 'about' frontmatter
      ---
      MARKDOWN
    end
    @repo.refs["refs/heads/master"].update(commit, @repo.owner)

    issue_templates = IssueTemplates.new(@repo)
    legacy_template = issue_templates.legacy_template

    assert_equal "issue-template.md", legacy_template.filename
    assert_equal "Default issue template", legacy_template.name
    assert_equal "default issue template", legacy_template.about
  end

  test "legacy issue template in the main folder has a name and about frontmatter by default" do
    commit = @repo.commits.create({ message: "Add templates", author: @repo.owner }) do |files|
      files.add "issue-template.md", <<~MARKDOWN
      > This is a legacy issue template
      which comes with a default 'name' and 'about' frontmatter
      ---
      MARKDOWN
    end
    @repo.refs["refs/heads/master"].update(commit, @repo.owner)

    issue_templates = IssueTemplates.new(@repo)
    legacy_template = issue_templates.legacy_template

    assert_equal "issue-template.md", legacy_template.filename
    assert_equal "Default issue template", legacy_template.name
    assert_equal "default issue template", legacy_template.about
  end

  test "omits issue templates with no front matter" do
    commit = @repo.commits.create({ message: "Add templates", committer: @repo.owner }) do |files|
      files.add ".github/ISSUE_TEMPLATE/bugs.md", <<~MARKDOWN
      ---
      name: Bug report
      about: It's a bug
      ---
      This is a bug.
      MARKDOWN

      files.add ".github/ISSUE_TEMPLATE/feature-request.md", <<~MARKDOWN
      This won't show up.
      MARKDOWN
    end
    @repo.refs["refs/heads/master"].update(commit, @repo.owner)

    issue_templates = IssueTemplates.new(@repo)
    assert_equal 1, issue_templates.valid_templates.size
  end

  test "omits issue templates with invalid YAML" do
    commit = @repo.commits.create({ message: "Add templates", committer: @repo.owner }) do |files|
      files.add ".github/ISSUE_TEMPLATE/bugs.md", <<~MARKDOWN
      ---
      name: Bug report
      about: It's a bug
      ---
      This is a bug.
      MARKDOWN

      files.add ".github/ISSUE_TEMPLATE/feature-request.md", <<~MARKDOWN
      ---
      name_bogus: Feature request
      ---
      This is a feature request.
      MARKDOWN
    end
    @repo.refs["refs/heads/master"].update(commit, @repo.owner)

    issue_templates = IssueTemplates.new(@repo)
    assert_equal 1, issue_templates.valid_templates.size
  end

  test "is case insensitive for the .md" do
    commit = @repo.commits.create({ message: "Add templates", committer: @repo.owner }) do |files|
      files.add ".github/ISSUE_TEMPLATE/feature-request.Md", <<~MARKDOWN
      ---
      name: Feature request
      about: It's a feature request
      ---
      This is a feature request.
      MARKDOWN
    end
    @repo.refs["refs/heads/master"].update(commit, @repo.owner)

    issue_templates = IssueTemplates.new(@repo)
    assert_equal 1, issue_templates.valid_templates.size
  end

  context "#find_by_name" do
    test "returns the matching issue_template" do
      commit = @repo.commits.create({ message: "Add templates", committer: @repo.owner }) do |files|
        files.add ".github/ISSUE_TEMPLATE/bugs.md", <<~MARKDOWN
        ---
        name: Bug report
        about: It's a bug
        ---
        This is a bug.
        MARKDOWN
      end
      @repo.refs["refs/heads/master"].update(commit, @repo.owner)

      issue_template = IssueTemplates.new(@repo).find_by_name("Bug report")
      assert_equal "Bug report", issue_template.name
      assert_equal "It's a bug", issue_template.about
    end

    test "returns nil for a non-matching name" do
      issue_template = IssueTemplates.new(@repo).find_by_name("No bug report")
      assert_nil issue_template
    end
  end

  context "#update" do
    test "can commit to master" do
      # required in order to verify commit is signed by GitHub.
      WebFlowHelper.setup_webflow

      issue_templates = IssueTemplates.new(@repo)

      templates = [
        { "bug.md" => "---\nname: Bug report\nabout: This is a bug report\n---" },
        { "feature.md" => "---\nname: Feature request\nabout: This is a feature request\n---" },
      ]

      result = issue_templates.update(templates, branch: "master", updater: @owner, commit_title: "Update the templates", commit_body: "", reflog_data: {})
      assert_predicate result, :ok?

      bug, feature = IssueTemplates.new(@repo).templates.sort_by(&:name)

      assert_equal "bug.md", bug.filename
      assert_equal "Bug report", bug.name
      assert_equal "This is a bug report", bug.about

      assert_equal "feature.md", feature.filename
      assert_equal "Feature request", feature.name
      assert_equal "This is a feature request", feature.about

      # ensure commit is signed by GitHub is enabled.
      if GitHub.web_commit_signing_enabled?
        issue_template_commit = @repo.refs["refs/heads/master"].commit

        assert_predicate issue_template_commit, :verified_signature?
      end
    end

    test "can commit to master in empty repository" do
      repo = create :repository, from_example: :empty

      issue_templates = IssueTemplates.new(repo)

      templates = [
        { "bug.md" => "---\nname: Bug report\nabout: This is a bug report\n---" },
      ]

      result = issue_templates.update(templates, branch: "master", updater: @owner, commit_title: "Update the templates", commit_body: "", reflog_data: {})
      assert_predicate result, :ok?, result.error

      bug = IssueTemplates.new(repo).templates.first

      assert_equal "bug.md", bug.filename
      assert_equal "Bug report", bug.name
      assert_equal "This is a bug report", bug.about
    end

    test "does not push an empty commit" do
      repo = create :repository, from_example: :empty

      issue_templates = IssueTemplates.new(repo)

      templates = [{}]

      result = issue_templates.update(templates, branch: "master", updater: @owner, commit_title: "Update the templates", commit_body: "", reflog_data: {})
      assert_equal "The commit cannot be empty", result.error
    end

    test "removes templates that aren't mentioned anymore" do
      issue_templates = IssueTemplates.new(@repo)

      templates = [
        { "hello.md" => "---\nname: Hello\nabout: This is hello\n---" },
        { "feature.md" => "---\nname: Feature request\nabout: This is a feature request\n---" },
      ]

      result = issue_templates.update(templates, branch: "master", updater: @owner, commit_title: "Update the templates", commit_body: "", reflog_data: {})
      assert_predicate result, :ok?
      assert_equal 2, IssueTemplates.new(@repo).templates.size
    end

    test "can create a PR" do
      # required in order to verify commit is signed by GitHub.
      WebFlowHelper.setup_webflow

      issue_templates = IssueTemplates.new(@repo)

      templates = [
        { "hello.md" => "---\nname: Hello\nabout: This is a bug report\n---" },
        { "feature.md" => "---\nname: Feature request\nabout: This is a feature request\n---" },
      ]

      result = issue_templates.update(templates, branch: "update-templates", updater: @owner, commit_title: "Update the templates", commit_body: "", reflog_data: {})
      assert_predicate result, :ok?

      pull_request = result.pull_request
      assert_equal "update-templates", pull_request.head_ref
      assert_equal "master", pull_request.base_ref
      assert_equal @owner, pull_request.user

      # ensure commit is signed by GitHub is enabled.
      if GitHub.web_commit_signing_enabled?
        issue_template_commit = @repo.refs["refs/heads/#{pull_request.head_ref}"].commit

        assert_predicate issue_template_commit, :verified_signature?
      end
    end
  end

  context ".valid_legacy_template_path" do
    test "is valid for issue-template.md filename with a -" do
      assert IssueTemplates.valid_legacy_template_path?("issue-template.md")
    end

    test "is valid for issue_template.md in the main directory" do
      assert IssueTemplates.valid_legacy_template_path?("issue_template.md")
    end

    test "is valid for case insenitive ISSUE_TEMPLATE.md in the main directory" do
      assert IssueTemplates.valid_legacy_template_path?("ISSUE_TEMPLATE.md")
    end

    test "is valid for issue_template.md in .github/ directory" do
      assert IssueTemplates.valid_legacy_template_path?(".github/issue_template.md")
    end

    test "is invalid for issue_template.md in .github/ISSUE_TEMPLATE directory" do
      refute IssueTemplates.valid_legacy_template_path?(".github/ISSUE_TEMPLATE/issue_template.md")
    end
  end

  context ".valid_path?" do
    test "true for path to markdown issue template" do
      assert IssueTemplates.valid_path?(".github/ISSUE_TEMPLATE/issue_template.md")
    end

    test "true for path to structured template" do
      assert IssueTemplates.valid_path?(".github/ISSUE_TEMPLATE/paimon.yml")
      assert IssueTemplates.valid_path?(".github/ISSUE_TEMPLATE/paimon.yaml")
    end

    test "false if yaml file is config file" do
      refute IssueTemplates.valid_path?(".github/ISSUE_TEMPLATE/config.yml")
    end

    test "false for file that is not markdown" do
      refute IssueTemplates.valid_path?(".github/ISSUE_TEMPLATE/klee.txt")
    end

    test "false if path is not for issue templates" do
      refute IssueTemplates.valid_path?(".github/cool_stuff/paimon.yml")
    end
  end
end
