# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueTemplateTest < GitHub::TestCase
  include DogstatsTestHelpers
  include MemexHelpers

  fixtures do
    @repo = create :repository, from_example: :simple
    @owner = @repo.owner

    @user = create :user
    @repo.add_member(@user)

    @rainbow_label = create(:label, name: "rainbow-skate", repository: @repo)
    @skaters_label = create(:label, name: "skaters", repository: @repo)

    @assignees_string = "#{@owner.login}, #{@user.login}"
    @labels_string = "#{@rainbow_label.name}, #{@skaters_label.name}"

    @org = create(:organization)
    @org_member = create(:verified_user)
    @org.add_member(@org_member)
    @org_repo = create(:repository, owner: @org)

    @org_project = create(:memex_project, owner: @org)
    @org_project_2 = create(:memex_project, owner: @org)

    @projects_string = "#{@org.login}/#{@org_project.number}, #{@org.login}/#{@org_project_2.number}"
    MemexHelpers.setup_organization_wide_access_for_projects("project_writer")
  end

  context "defaults" do
    test "has a default bug report" do
      template = IssueTemplate.default(:bug, repository: @repo)
      assert_equal "Bug report", template.name
    end

    test "has a default feature" do
      template = IssueTemplate.default(:feature, repository: @repo)
      assert_equal "Feature request", template.name
    end
  end

  test "can create valid issue template" do
    issue_template = IssueTemplate.new(repository: @repo, filename: "bug.md", name: "Bug report", about: "Found a bug?", body: "")
    assert_predicate issue_template, :valid?
  end

  test "name is required" do
    issue_template = IssueTemplate.new(repository: @repo, filename: "bug.md", name: "", about: "Found a bug?", body: "")
    refute_predicate issue_template, :valid?
    assert issue_template.errors[:name].present?
  end

  test "name must be fewer than 200 characters" do
    issue_template = IssueTemplate.new(repository: @repo, filename: "bug.md", name: "*" * 201, about: "Found a bug?", body: "")
    refute_predicate issue_template, :valid?
    assert issue_template.errors[:name].present?
  end

  test "name must be more than 3 characters" do
    issue_template = IssueTemplate.new(repository: @repo, filename: "bug.md", name: "hi", about: "Found a bug?", body: "")
    refute_predicate issue_template, :valid?
    assert issue_template.errors[:name].present?
  end

  test "about must be fewer than 200 characters" do
    issue_template = IssueTemplate.new(repository: @repo, filename: "bug.md", name: "Bug", about: "*" * 201, body: "")
    refute_predicate issue_template, :valid?
    assert issue_template.errors[:about].present?
    refute issue_template.errors[:description].present?
    assert_equal issue_template.errors[:about].first, "must be between 3 and 200 characters"
  end

  test "about must be fewer than 200 characters yaml reports error using description field" do
    issue_template = IssueTemplate.new(repository: @repo, filename: "bug.yml", name: "Bug", about: "*" * 201, body: "")
    refute_predicate issue_template, :valid?
    assert issue_template.errors[:description].present?
    refute issue_template.errors[:about].present?
    assert_equal issue_template.errors[:description].first, "must be between 3 and 200 characters"
  end

  test "about must be more than 3 characters" do
    issue_template = IssueTemplate.new(repository: @repo, filename: "bug.md", name: "Bug", about: "hi", body: "")
    refute_predicate issue_template, :valid?
    assert issue_template.errors[:about].present?
  end

  context "#name_uniqueness" do
    test "name must not clash with an existing template, where the filenames are different" do
      commit = @repo.commits.create({ message: "Add templates", committer: @owner }) do |files|
        files.add ".github/ISSUE_TEMPLATE/bugs.md", <<~MARKDOWN
        ---
        name: Duplicate name
        about: It's a bug
        ---
        This is a bug.
        MARKDOWN
      end

      @repo.refs["refs/heads/master"].update(commit, @owner)

      issue_template = IssueTemplate.new(repository: @repo, filename: "bug2.md", name: "Duplicate name", about: "hi", body: "")
      refute_predicate issue_template, :valid?
      assert issue_template.errors[:name].present?
    end

    test "validation should not error when the same file is being modified" do
      commit = @repo.commits.create({ message: "Add templates", committer: @owner }) do |files|
        files.add ".github/ISSUE_TEMPLATE/bugs.md", <<~MARKDOWN
        ---
        name: Modified template
        about: It's a bug
        ---
        This is a bug.
        MARKDOWN
      end

      @repo.refs["refs/heads/master"].update(commit, @owner)

      issue_template = IssueTemplate.new(repository: @repo, filename: "bugs.md", name: "Modified template", about: "It's a really bad bug!", body: "")
      assert_predicate issue_template, :valid?
    end

    test "validation should not error when the name clash involves a file going from .md -> .yml or .yaml extension, when feature flag enabled" do
      commit = @repo.commits.create({ message: "Add templates", committer: @owner }) do |files|
        files.add ".github/ISSUE_TEMPLATE/bugs.md", <<~MARKDOWN
        ---
        name: Modified template
        about: It's a bug
        ---
        This is a bug.
        MARKDOWN
      end
      @repo.refs["refs/heads/master"].update(commit, @owner)

      raw_data = <<~YAML
        ---
        name: Modified template
        description: Create a report to help us improve
        body:
        - type: input
          attributes:
            label: "what is your bug?"
        YAML

      config = IssueForms::TemplateConfig.new(input: raw_data, path: "bugs.yaml").load
      issue_template = IssueTemplate.new_from_structured_template_config(config: config, repository: @repo, filename: "bugs.yaml")
      assert_predicate issue_template, :valid?
    end
  end

  test "#labels returns Labels associated to the current repo from the labels_string provided" do
    issue_template = IssueTemplate.new(repository: @repo, filename: "bug.md", name: "bug report", about: "Found a bug?", body: "", labels_string: @labels_string)

    refute_empty issue_template.labels
    assert_includes issue_template.labels, @rainbow_label
    assert_includes issue_template.labels, @skaters_label
  end

  test "#assignees returns assignees associated to the issue template from the assignees_string provided" do
    issue_template = IssueTemplate.new(repository: @repo, filename: "bug.md", name: "bug report", about: "Found a bug?", body: "", assignees_string: @assignees_string)

    refute_empty issue_template.assignees
    assert_includes issue_template.assignees, @owner
    assert_includes issue_template.assignees, @user
  end

  test "#projects returns projects associated to the issue template from the projects_string provided if user has project access" do
    issue_template = IssueTemplate.new(repository: @org_repo, filename: "bug.md", name: "bug report", about: "Found a bug?", body: "", projects_string: @projects_string, user: @org_member)

    refute_empty issue_template.projects
    assert_includes issue_template.projects, @org_project
    assert_includes issue_template.projects, @org_project_2
  end

  test "#projects does not return projects from the projects_string provided if user has no project access" do
    issue_template = IssueTemplate.new(repository: @org_repo, filename: "bug.md", name: "bug report", about: "Found a bug?", body: "", projects_string: @projects_string, user: @user)
    assert_empty issue_template.projects
  end

  test "#issue returns a new issue" do
    issue_template = IssueTemplate.new(repository: @repo, filename: "bug.md", name: "bug report", about: "Found a bug?", body: "")
    issue = issue_template.issue

    assert_instance_of Issue, issue
    assert issue.new_record?
  end

  test "#issue returns a new issue with associated labels if labels_string is provided" do
    issue_template = IssueTemplate.new(repository: @repo, filename: "bug.md", name: "bug report", about: "Found a bug?", body: "", labels_string: @labels_string)
    issue = issue_template.issue

    refute_empty issue.labels
    assert_includes issue.labels, @rainbow_label
    assert_includes issue.labels, @skaters_label
  end

  test "#issue returns a new issue with associated assignees if assignees_string is provided" do
    issue_template = IssueTemplate.new(repository: @repo, filename: "bug.md", name: "bug report", about: "Found a bug?", body: "", assignees_string: @assignees_string)
    issue = issue_template.issue

    refute_empty issue.assignees
    assert_includes issue.assignees, @owner
    assert_includes issue.assignees, @user
  end

  test "#issue returns a new issue with associated projects if projects_string provided" do
    issue_template = IssueTemplate.new(repository: @org_repo, filename: "bug.md", name: "bug report", about: "Found a bug?", body: "", projects_string: @projects_string, user: @org_member)
    issue = issue_template.issue

    refute_empty issue.memex_projects
    assert_includes issue.memex_projects, @org_project
    assert_includes issue.memex_projects, @org_project_2
  end

  test "#issue returns a new issue with no projects if projects_string provided and user does not have access" do
    issue_template = IssueTemplate.new(repository: @org_repo, filename: "bug.md", name: "bug report", about: "Found a bug?", body: "", projects_string: @projects_string, user: @user)
    issue = issue_template.issue
    assert_empty issue.memex_projects
  end

  context "#uses?" do
    test "returns true for used fields" do
      issue_template = IssueTemplate.from_hash(@repo, {
        filename: "bug.yml",
        name: "test",
        about: "test",
        title: "title",
        labels: "foo, bar",
        assignees: "bug",
        projects: ["monalisa/1"]
      }.with_indifferent_access)

      assert issue_template.uses?(:title)
      assert issue_template.uses?(:labels)
      assert issue_template.uses?(:assignees)
      assert issue_template.uses?(:projects)
    end

    test "returns false for blank fields" do
      issue_template = IssueTemplate.from_hash(@repo, {
        filename: "bug.yml",
        name: "test",
        about: "test",
        title: "",
        projects: "",
      }.with_indifferent_access)

      refute issue_template.uses?(:title)
      refute issue_template.uses?(:projects)

    end
  end

  context "#structured?" do
    test "returns true for structured templates when feature flag is enabled" do
      %w[yml yaml].each do |ext|
        template = IssueTemplate.new(
          repository: @repo,
          filename: "bug.#{ext}",
          name: "Bug report",
          about: "Found a bug?",
          body: "",
        )

        assert_predicate template, :structured?
      end
    end

    test "returns false for markdown file" do
      template = IssueTemplate.new(
        repository: @repo,
        filename: "bug.md",
        name: "Bug report",
        about: "Found a bug?",
        body: "",
      )

      refute_predicate template, :structured?
    end
  end

  context "#project_count" do
    test "returns number of projects in issue form" do
      issue_template_with_4_projects = IssueTemplate.from_hash(@repo, {
        name: "test",
        filename: "bug.yml",
        about: "test",
        title: "title",
        labels: "foo, bar",
        assignees: "bug",
        projects: "monalisa/1,monalisa/2,monalisa/3,monalisa/4"
      }.with_indifferent_access)

      issue_template_with_1_project = IssueTemplate.from_hash(@repo, {
        name: "test",
        filename: "bug.yml",
        about: "test",
        title: "title",
        labels: "foo, bar",
        assignees: "bug",
        projects: ["monalisa/1"]
      }.with_indifferent_access)

      issue_template_with_no_projects = IssueTemplate.from_hash(@repo, {
        name: "test",
        filename: "bug.yml",
        about: "test",
        title: "title",
        labels: "foo, bar",
        assignees: "bug",
      }.with_indifferent_access)

      assert_equal 4, issue_template_with_4_projects.project_count
      assert_equal 1, issue_template_with_1_project.project_count
      assert_equal 0, issue_template_with_no_projects.project_count


    end
  end

  context ".from_tree_entry" do
    test "creates template from markdown file" do
      commit = @repo.commits.create({ message: "Add templates", committer: @owner }) do |files|
        files.add ".github/ISSUE_TEMPLATE/dorte.md", <<~MARKDOWN
        ---
        name: Dorte the horse
        about: Report an issue at the stables.
        type: P1 Wow
        ---
        Tell Marianne about the issue:
        MARKDOWN
      end

      @repo.refs["refs/heads/master"].update(commit, @owner)
      tree_entry = @repo.directory(
        @repo.default_oid,
        IssueTemplates.template_directory,
      ).tree_entries.first

      template = IssueTemplate.from_tree_entry(tree_entry)
      assert_equal "Dorte the horse", template.name
      assert_equal "Report an issue at the stables.", template.about
      assert_equal "Tell Marianne about the issue:\n", template.body
      assert_equal "P1 Wow", template.type
    end

    test "include_body? is true for markdown templates" do
      commit = @repo.commits.create({ message: "Add templates", committer: @owner }) do |files|
        files.add ".github/ISSUE_TEMPLATE/dorte.md", <<~MARKDOWN
        ---
        name: Dorte the horse
        about: Report an issue at the stables.
        ---
        Tell Marianne about the issue:
        MARKDOWN
      end

      @repo.refs["refs/heads/master"].update(commit, @owner)
      tree_entry = @repo.directory(
        @repo.default_oid,
        IssueTemplates.template_directory,
      ).tree_entries.first

      template = IssueTemplate.from_tree_entry(tree_entry)
      assert_equal "Dorte the horse", template.name
      assert_equal "Report an issue at the stables.", template.about
      assert_equal "Tell Marianne about the issue:\n", template.body
      assert_predicate template, :include_body?
    end

    test "creates template from structured template file if feature flag is enabled" do
      commit = @repo.commits.create({ message: "Add templates", committer: @owner }) do |files|
        files.add ".github/ISSUE_TEMPLATE/structured_example_1.yaml", <<~YAML
        ---
        name: Structured example valid
        description: Paimon likes sticky honey roast.
        labels: cooking
        assignees: paimon
        body:
        - type: textarea
          attributes:
            label: "Why do you stan Hatsune Miku?"
        YAML
      end

      @repo.refs["refs/heads/master"].update(commit, @owner)
      tree_entry = @repo.directory(
        @repo.default_oid,
        IssueTemplates.template_directory,
      ).tree_entries.first

      template = IssueTemplate.from_tree_entry(tree_entry)
      assert_predicate template, :valid?
      assert_equal "Structured example valid", template.name
      assert_equal "Paimon likes sticky honey roast.", template.about
      assert_equal "cooking", template.labels_string
      assert_equal "paimon", template.assignees_string
    end

    test "returns errors for structured template file with invalid formatting" do
      commit = @repo.commits.create({ message: "Add templates", committer: @owner }) do |files|
        files.add ".github/ISSUE_TEMPLATE/structured_example_3.yaml", <<~YAML
        ---
        name: Structured example invalid formatting
        about: [
        YAML
      end

      @repo.refs["refs/heads/master"].update(commit, @owner)
      tree_entry = @repo.directory(
        @repo.default_oid,
        IssueTemplates.template_directory,
      ).tree_entries.first

      template = IssueTemplate.from_tree_entry(tree_entry)
      refute_predicate template, :valid?
      assert_equal ["YAML syntax error: (<unknown>): did not find expected node content while parsing a flow node at line 4 column 1"],
                   template.errors.full_messages
    end

    test "does not return TypeError with invalid markdown format" do
      commit = @repo.commits.create({ message: "Add templates", committer: @owner }) do |files|
        files.add ".github/ISSUE_TEMPLATE/dorte.md", <<~MARKDOWN
        ---
        1
        ---
        MARKDOWN
      end

      @repo.refs["refs/heads/master"].update(commit, @owner)
      tree_entry = @repo.directory(@repo.default_oid,
          IssueTemplates.template_directory,
        ).tree_entries.first

      # check that errors are not raised
      assert_nothing_raised do
        IssueTemplate.from_tree_entry(tree_entry)
      end

      template = IssueTemplate.from_tree_entry(tree_entry)
      refute_predicate template, :valid?
      assert template.errors[:name].present?
      assert template.errors[:about].present?
      assert_equal ["Name can't be blank", "About can't be blank"], template.errors.full_messages
    end
  end

  context ".new_from_structured_template_config" do
    test "creates new issue template from IssueForms::TemplateConfig" do
      input = <<~YAML
      ---
      name: Paimon
      description: Paimon likes sticky honey roast.
      title: default title
      labels: cooking
      assignees: paimon
      body:
        - type: textarea
          attributes:
            label: "Why do you stan Hatsune Miku?"
      YAML

      config = IssueForms::TemplateConfig.new(input: input, path: "").load

      template = IssueTemplate.new_from_structured_template_config(
        config: config,
        repository: @repo,
        filename: "paimon.yml",
      )

      assert_predicate template, :valid?
      assert_equal "Paimon", template.name
      assert_equal "Paimon likes sticky honey roast.", template.about
      assert_equal "default title", template.title
      assert_equal "cooking", template.labels_string
      assert_equal "paimon", template.assignees_string
      input = template.inputs.first
      assert_equal "textarea", input.type
      assert_equal "Why do you stan Hatsune Miku?", input.label
    end

    test "includes user_inputs" do
      input = <<~YAML
      name: Paimon
      description: Paimon likes sticky honey roast.
      title: default title
      body:
        - type: markdown
          attributes:
            value: "Example description"
        - type: textarea
          attributes:
            label: "Why do you stan Hatsune Miku?"
      YAML

      config = IssueForms::TemplateConfig.new(input: input, path: "").load

      template = IssueTemplate.new_from_structured_template_config(
        config: config,
        repository: @repo,
        filename: "paimon.yml",
      )

      assert_predicate template, :valid?
      assert_equal 2, template.inputs.count
      assert_equal 1, template.user_inputs.count
      assert_equal "Why do you stan Hatsune Miku?", template.user_inputs.first.label
    end

    test "converts labels and assignees from arrays into comma-delimited strings" do
      input = <<~YAML
      name: Paimon
      description: Paimon likes sticky honey roast.
      labels: ["bug:triage", "feature:small"]
      assignees: [denise, evelyn]
      body:
        - type: textarea
          attributes:
            label: "Why do you stan Hatsune Miku?"
      YAML

      config = IssueForms::TemplateConfig.new(input: input, path: "").load

      template = IssueTemplate.new_from_structured_template_config(
        config: config,
        repository: @repo,
        filename: "paimon.yml",
        )

      assert_predicate template, :valid?
      assert_equal "denise,evelyn", template.assignees_string
      assert_equal "bug:triage,feature:small", template.labels_string
    end

    test "returns errors for IssueForms::TemplateConfig, overriding issue template errors" do
      input = <<~YAML
      ---
      name: Bad template with no user input
      body: []
      YAML

      config = IssueForms::TemplateConfig.new(input: input, path: "").load

      template = IssueTemplate.new_from_structured_template_config(
        config: config,
        repository: @repo,
        filename: "paimon.yml",
      )

      refute_predicate template, :valid?
      assert_equal ["Body cannot be empty"], template.errors.full_messages
    end

    test "includes type field if FF is enabled" do
      input = <<~YAML
      ---
      name: Paimon
      description: Paimon likes sticky honey roast.
      title: default title
      type: Bug
      body:
        - type: textarea
          attributes:
            label: "Why do you stan Hatsune Miku?"
      YAML

      config = IssueForms::TemplateConfig.new(input: input, path: "", type_field_enabled: true).load

      template = IssueTemplate.new_from_structured_template_config(
        config: config,
        repository: @repo,
        filename: "paimon.yml",
      )

      assert_predicate template, :valid?
      assert_equal "Bug", template.type
    end

    test "throws error if type field is present but FF is disabled" do
      input = <<~YAML
      ---
      name: Paimon
      description: Paimon likes sticky honey roast.
      title: default title
      type: Bug
      body:
        - type: textarea
          attributes:
            label: "Why do you stan Hatsune Miku?"
      YAML

      config = IssueForms::TemplateConfig.new(input: input, path: "").load

      template = IssueTemplate.new_from_structured_template_config(
        config: config,
        repository: @repo,
        filename: "paimon.yml",
      )

      refute_predicate template, :valid?
      assert template.config_errors.any? { |error| error.message.include?("`type` is not a permitted key") }
    end
  end

  context "#labels_string" do
    test "returns string containing labels for template" do
      commit = @repo.commits.create({ message: "Add templates", committer: @owner }) do |files|
        files.add ".github/ISSUE_TEMPLATE/dorte.md", <<~MARKDOWN
        ---
        name: Dorte the horse
        about: Report an issue at the stables.
        labels: test, another-label
        ---
        Tell Marianne about the issue:
        MARKDOWN
      end

      @repo.refs["refs/heads/master"].update(commit, @owner)
      tree_entry = @repo.directory(
        @repo.default_oid,
        IssueTemplates.template_directory,
      ).tree_entries.first

      template = IssueTemplate.from_tree_entry(tree_entry)
      assert_equal "test, another-label", template.labels_string
    end

    test "returns string if labels is specified as array" do
      commit = @repo.commits.create({ message: "Add templates", committer: @owner }) do |files|
        files.add ".github/ISSUE_TEMPLATE/dorte.md", <<~MARKDOWN
        ---
        name: Dorte the horse
        about: Report an issue at the stables.
        labels: [test, another-label]
        ---
        Tell Marianne about the issue:
        MARKDOWN
      end

      @repo.refs["refs/heads/master"].update(commit, @owner)
      tree_entry = @repo.directory(
        @repo.default_oid,
        IssueTemplates.template_directory,
      ).tree_entries.first

      template = IssueTemplate.from_tree_entry(tree_entry)
      assert_equal "test,another-label", template.labels_string
    end
  end

  context "#assignees_string" do
    test "returns string containing assignees for template" do
      commit = @repo.commits.create({ message: "Add templates", committer: @owner }) do |files|
        files.add ".github/ISSUE_TEMPLATE/dorte.md", <<~MARKDOWN
        ---
        name: Dorte the horse
        about: Report an issue at the stables.
        assignees: marianne
        ---
        Tell Marianne about the issue:
        MARKDOWN
      end

      @repo.refs["refs/heads/master"].update(commit, @owner)
      tree_entry = @repo.directory(
        @repo.default_oid,
        IssueTemplates.template_directory,
      ).tree_entries.first

      template = IssueTemplate.from_tree_entry(tree_entry)
      assert_equal "marianne", template.assignees_string
    end

    test "returns string if assignees is specified as array" do
      commit = @repo.commits.create({ message: "Add templates", committer: @owner }) do |files|
        files.add ".github/ISSUE_TEMPLATE/dorte.md", <<~MARKDOWN
        ---
        name: Dorte the horse
        about: Report an issue at the stables.
        assignees: [marianne]
        ---
        Tell Marianne about the issue:
        MARKDOWN
      end

      @repo.refs["refs/heads/master"].update(commit, @owner)
      tree_entry = @repo.directory(
        @repo.default_oid,
        IssueTemplates.template_directory,
      ).tree_entries.first

      template = IssueTemplate.from_tree_entry(tree_entry)
      assert_equal "marianne", template.assignees_string
    end
  end

  context "#track_required_inputs" do
    test "increments required_fields:0 if no required fields" do
      raw_data = <<~YAML
      ---
      name: Modified template
      description: Create a report to help us improve
      body:
      - type: input
        attributes:
          label: "what is your bug?"
      YAML

      config = IssueForms::TemplateConfig.new(input: raw_data, path: "bugs.yaml").load
      issue_template = IssueTemplate.new_from_structured_template_config(config: config, repository: @repo, filename: "bugs.yaml")

      issue_template.track_required_inputs(action: :new)
      assert_dogstats_increment 1, "issues.with_template", tags: [
        "action:new",
        "owner_type:User",
        "repo_visibility:public",
        "required_fields:0"
      ]
    end

    test "increments required_fields:1-50 for 1-50% of required fields" do
      raw_data = <<~YAML
      ---
      name: Modified template
      description: Create a report to help us improve
      body:
      - type: input
        attributes:
          label: "1"
      - type: input
        attributes:
          label: "2"
        validations:
          required: true
      - type: input
        attributes:
          label: "3"
      YAML

      config = IssueForms::TemplateConfig.new(input: raw_data, path: "bugs.yaml").load
      issue_template = IssueTemplate.new_from_structured_template_config(config: config, repository: @repo, filename: "bugs.yaml")

      issue_template.track_required_inputs(action: :new)
      assert_dogstats_increment 1, "issues.with_template", tags: [
        "action:new",
        "owner_type:User",
        "repo_visibility:public",
        "required_fields:1-50"
      ]
    end

    test "increments required_fields:51-75 for 51-75% of required fields" do
      raw_data = <<~YAML
      ---
      name: Modified template
      description: Create a report to help us improve
      body:
      - type: input
        attributes:
          label: "1"
      - type: input
        attributes:
          label: "2"
        validations:
          required: true
      - type: input
        attributes:
          label: "3"
        validations:
          required: true
      YAML

      config = IssueForms::TemplateConfig.new(input: raw_data, path: "bugs.yaml").load
      issue_template = IssueTemplate.new_from_structured_template_config(config: config, repository: @repo, filename: "bugs.yaml")

      issue_template.track_required_inputs(action: :new)
      assert_dogstats_increment 1, "issues.with_template", tags: [
        "action:new",
        "owner_type:User",
        "repo_visibility:public",
        "required_fields:51-75"
      ]
    end

    test "increments required_fields:76-100 for 76-100% of required fields" do
      raw_data = <<~YAML
      ---
      name: Modified template
      description: Create a report to help us improve
      body:
      - type: input
        attributes:
          label: "1"
        validations:
          required: true
      YAML

      config = IssueForms::TemplateConfig.new(input: raw_data, path: "bugs.yaml").load
      issue_template = IssueTemplate.new_from_structured_template_config(config: config, repository: @repo, filename: "bugs.yaml")

      issue_template.track_required_inputs(action: :new)
      assert_dogstats_increment 1, "issues.with_template", tags: [
        "action:new",
        "owner_type:User",
        "repo_visibility:public",
        "required_fields:76-100"
      ]
    end

    test "does not increment if there are no user inputs" do
      raw_data = <<~YAML
      ---
      name: Modified template
      description: Create a report to help us improve
      body: []
      YAML

      config = IssueForms::TemplateConfig.new(input: raw_data, path: "bugs.yaml").load
      issue_template = IssueTemplate.new_from_structured_template_config(config: config, repository: @repo, filename: "bugs.yaml")

      issue_template.track_required_inputs(action: :new)
      assert_dogstats_increment 0, "issues.with_template"
    end
  end
end
