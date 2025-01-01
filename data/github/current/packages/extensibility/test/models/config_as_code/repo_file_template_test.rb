# typed: true
# frozen_string_literal: true

require "test_helper"

class RepoFileTemplateTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, from_example: :dot_github)

    @bugs_yaml = <<~YML
    name: Bug Template
    description: It's a bug
    body:
      - type: input
        attributes:
          name: Operating System
          description: What operating system are you using?
          placeholder: ex. OSX Mountain Lion
          value: "operating system"
        validations:
          required: true
    YML

    @funtimes_yaml = <<~YML
    name: Fun Times
    description: It's a party
    body:
      - type: input
        attributes:
          label: Operating System
          description: What operating system are you using?
          placeholder: ex. OSX Mountain Lion
          value: "operating system"
        validations:
          required: true
    YML
    @invalid_array_schema_yaml = <<~YML
    - type: input
      attributes:
        name: Operating System
        description: What operating system are you using?
        placeholder: ex. OSX Mountain Lion
        value: "operating system"
      validations:
        required: true
    YML
    @invalid_yaml = <<~YML
    name: Duplicate name
    description: It's a bug
    body:
      - type: input
        attributes:
          name: 1
          description: What operating system are you using?
          placeholder: ex. OSX Mountain Lion
          value: "operating system"
        validations:
          required: 2
    YML
  end

  setup do
    GitHub.flipper[:slash_commands].enable
    GitHub.flipper[:structured_issue_comment_templates].enable
  end

  context "#ConfigAsCode::RepoFileTemplate" do
    context "::YamlTemplate" do
      test "Initialize a Valid Template" do
        tree_entry = commit_file(@repo, "Add structured template", ConfigAsCode::RepoFileTemplate::ISSUE_COMMENT_TEMPLATE, "goodtimes.yml", "")
        template = ConfigAsCode::RepoFileTemplate::YamlTemplate.new(@repo, @funtimes_yaml, "goodtimes.yml".dup, tree_entry, UI::FormSchema::TemplateValidator)
        assert_predicate template, :valid?
        assert_equal template.name, "Fun Times"
        assert_equal template.about, "It's a party"
        assert_equal template.description, "It's a party"
        assert_equal template.filename, "goodtimes.yml"
      end

      test "Initialize an invalid template with an array data structure" do
        tree_entry = commit_file(@repo, "Add structured template", ConfigAsCode::RepoFileTemplate::ISSUE_COMMENT_TEMPLATE, "goodtimes.yml", "")
        template = ConfigAsCode::RepoFileTemplate::YamlTemplate.new(@repo, @invalid_array_schema_yaml, "invalid.yml".dup, tree_entry, UI::FormSchema::TemplateValidator)
        refute_predicate template, :valid?
        assert_nil template.name
        assert_nil template.about
        assert_nil template.description
        assert_equal template.filename, "invalid.yml"
      end

      test "Initialize a empty Template" do
        tree_entry = commit_file(@repo, "Add structured template", ConfigAsCode::RepoFileTemplate::ISSUE_COMMENT_TEMPLATE, "badtimes.yml", "")
        template = ConfigAsCode::RepoFileTemplate::YamlTemplate.new(@repo, "", "badtimes.yml".dup, tree_entry, UI::FormSchema::TemplateValidator)
        assert_equal template.filename, "badtimes.yml"
        refute_predicate template, :valid?
        assert_nil template.name
        assert_nil template.about
        assert_nil template.description
        assert_nil template.body
      end

      test "Initialize an Invalid Template" do
        tree_entry = commit_file(@repo, "Add structured template", ConfigAsCode::RepoFileTemplate::ISSUE_COMMENT_TEMPLATE, "badtimes.yml", @invalid_yaml)
        template = ConfigAsCode::RepoFileTemplate::YamlTemplate.new(@repo, @invalid_yaml, "badtimes.yml".dup, tree_entry, UI::FormSchema::TemplateValidator)
        refute_predicate template, :valid?
        assert_equal "Duplicate name", template.name
        assert_equal "It's a bug", template.about
        assert_equal "It's a bug", template.description
        refute_nil template.body
      end

      test "Initialize Invalid YAML" do
        yml = <<~YML
        bad: yes
        -
        YML

        tree_entry = commit_file(@repo, "Add structured template", ConfigAsCode::RepoFileTemplate::ISSUE_COMMENT_TEMPLATE, "badtimes.yml", yml)

        template = ConfigAsCode::RepoFileTemplate::YamlTemplate.new(@repo, yml, "badtimes.yml".dup, tree_entry, UI::FormSchema::TemplateValidator)
        assert_equal template.filename, "badtimes.yml"
        refute_predicate template, :valid?
        assert_nil template.name
        assert_nil template.about
        assert_nil template.description
        assert_nil template.body
      end

      test "Initialize YAML without a name" do
        yml = <<~YML
          body:
            - label: Reproducemepls
              type: Input.Text
        YML

        tree_entry = commit_file(@repo, "Add structured template", ConfigAsCode::RepoFileTemplate::ISSUE_COMMENT_TEMPLATE, "no_name.yml", yml)
        template = ConfigAsCode::RepoFileTemplate::YamlTemplate.new(@repo, yml, "no_name.yml".dup, tree_entry, UI::FormSchema::TemplateValidator)
        assert_equal template.filename, "no_name.yml"
        refute_predicate template, :valid?
      end

      test "Initialize YAML with an invalid name" do
        yml = <<~YML
          name:
            - detailed_name: this is not valid
          body:
            - label: Reproducemepls
              type: Input.Text
        YML

        tree_entry = commit_file(@repo, "Add structured template", ConfigAsCode::RepoFileTemplate::ISSUE_COMMENT_TEMPLATE, "invalid_name.yml", yml)
        template = ConfigAsCode::RepoFileTemplate::YamlTemplate.new(@repo, yml, "invalid_name.yml".dup, tree_entry, UI::FormSchema::TemplateValidator)

        assert_equal template.filename, "invalid_name.yml"
        refute_predicate template, :valid?
      end

      test "Initialize YAML without a body" do
        yml = <<~YML
          name: no body
        YML

        tree_entry = commit_file(@repo, "Add structured template", ConfigAsCode::RepoFileTemplate::ISSUE_COMMENT_TEMPLATE, "no_body.yml", yml)
        template = ConfigAsCode::RepoFileTemplate::YamlTemplate.new(@repo, yml, "no_body.yml".dup, tree_entry, UI::FormSchema::TemplateValidator)

        assert_equal "no_body.yml", template.filename
        refute_predicate template, :valid?
      end

      test "Initialize YAML with an invalid body" do
        yml = <<~YML
          name: invalid_body
          body: invalid body!
        YML

        tree_entry = commit_file(@repo, "Add structured template", ConfigAsCode::RepoFileTemplate::ISSUE_COMMENT_TEMPLATE, "invalid_body.yml", yml)
        template = ConfigAsCode::RepoFileTemplate::YamlTemplate.new(@repo, yml, "invalid_body.yml".dup, tree_entry, UI::FormSchema::TemplateValidator)

        assert_equal template.filename, "invalid_body.yml"
        refute_predicate template, :valid?
      end

      test "Initialize YAML with an invalid description" do
        yml = <<~YML
          name: invalid_body
          description:
            - invalid_format: this is invalid
          body:
            - type: input
              attributes:
                name: name
        YML

        tree_entry = commit_file(@repo, "Add structured template", ConfigAsCode::RepoFileTemplate::ISSUE_COMMENT_TEMPLATE, "invalid_description.yml", yml)
        template = ConfigAsCode::RepoFileTemplate::YamlTemplate.new(@repo, yml, "invalid_description.yml".dup, tree_entry, UI::FormSchema::TemplateValidator)

        assert_equal template.filename, "invalid_description.yml"
        refute_predicate template, :valid?
      end
    end

    context "::MarkdownTemplate" do
      test "Initialize a Valid Template" do
        goodtimes_md = <<~MD
          # Goodtimes!
          _good_ *times*
        MD

        tree_entry = commit_file(@repo, "Add structured template", ConfigAsCode::RepoFileTemplate::ISSUE_COMMENT_TEMPLATE, "goodtimes.md", goodtimes_md)

        template = ConfigAsCode::RepoFileTemplate::MarkdownTemplate.new(@repo, goodtimes_md, "good-times.md".dup, tree_entry)
        assert_predicate template, :valid?
        assert_equal template.name, "Good times"
        assert_equal template.filename, "good-times.md"
        assert_equal template.tree_entry, tree_entry
      end
    end
  end

  context "self.description" do
    test "returns nil, when no feature flags are enabled" do
      GitHub.flipper[:slash_commands].disable
      GitHub.flipper[:structured_issue_comment_templates].disable

      assert_nil ConfigAsCode::RepoFileTemplate.description(
        @repo, ConfigAsCode::RepoFileTemplate::ISSUE_COMMENT_TEMPLATE + "/status.yml", @repo.owner
      )

      assert_nil ConfigAsCode::RepoFileTemplate.description(
        @repo, ConfigAsCode::RepoFileTemplate::COMMAND_CONFIG + "/status.yml", @repo.owner
      )
    end

    context "when slash_commands is enabled" do
      test "returns the /commands yaml description" do
        assert_equal "custom slash command", ConfigAsCode::RepoFileTemplate.description(
          @repo, ConfigAsCode::RepoFileTemplate::COMMAND_CONFIG + "/status.yml", @repo.owner
        )
      end
    end

    context "when structured_issue_comment_templates is enabled" do
      test "returns the /ISSUE_COMMENT_TEMPLATE yaml description" do
        assert_equal "issue comment template", ConfigAsCode::RepoFileTemplate.description(
          @repo, ConfigAsCode::RepoFileTemplate::ISSUE_COMMENT_TEMPLATE + "/status.yml", @repo.owner
        )
      end
    end
  end

  context "self.slash_commands_configuration_path?" do
    test "returns false when slash_commands is disabled" do
      GitHub.flipper[:slash_commands].disable

      refute ConfigAsCode::RepoFileTemplate.slash_commands_configuration_path?(
        @repo, ConfigAsCode::RepoFileTemplate::COMMAND_CONFIG + "/command.yml", @repo.owner
      )
    end

    test "returns false when the path doesnt match" do
      refute ConfigAsCode::RepoFileTemplate.slash_commands_configuration_path?(
        @repo, ConfigAsCode::RepoFileTemplate::COMMAND_CONFIG + "/readme.md", @repo.owner
      )
    end

    test "returns true when the path matches" do
      assert ConfigAsCode::RepoFileTemplate.slash_commands_configuration_path?(
        @repo, ConfigAsCode::RepoFileTemplate::COMMAND_CONFIG + "/command.yaml", @repo.owner
      )
    end
  end

  context "self.docs_url" do
    test "returns nil, when no feature flags are enabled" do
      GitHub.flipper[:slash_commands].disable

      assert_nil ConfigAsCode::RepoFileTemplate.docs_url(
        @repo, ConfigAsCode::RepoFileTemplate::COMMAND_CONFIG, @repo.owner
      )
    end

    context "when slash_commands is enabled" do
      test "returns the /commands yaml docs url" do
        assert_equal(
          "#{GitHub.help_url}/early-access/github/save-time-with-slash-commands/syntax-for-user-defined-slash-commands",
          ConfigAsCode::RepoFileTemplate.docs_url(@repo, ConfigAsCode::RepoFileTemplate::COMMAND_CONFIG + "/status.yml", @repo.owner)
        )
      end
    end
  end

  context "self.for_path" do
    test "returns nil, when no feature flags are enabled" do
      GitHub.flipper[:slash_commands].disable
      GitHub.flipper[:structured_issue_comment_templates].disable

      assert_nil ConfigAsCode::RepoFileTemplate.for_path(
        @repo, ConfigAsCode::RepoFileTemplate::ISSUE_COMMENT_TEMPLATE + "/status.yml", @repo.owner
      )

      assert_nil ConfigAsCode::RepoFileTemplate.for_path(
        @repo, ConfigAsCode::RepoFileTemplate::COMMAND_CONFIG + "/status.yml", @repo.owner
      )
    end

    context "when slash_commands is enabled" do
      test "returns the repo file template for the given path" do
        repo_file_template = ConfigAsCode::RepoFileTemplate.for_path(
          @repo, ConfigAsCode::RepoFileTemplate::COMMAND_CONFIG + "/status.yml", @repo.owner
        )
        refute_nil repo_file_template
        assert_equal SlashCommands::Validator, repo_file_template.validator_class
      end

      test "passes oid along" do
        ConfigAsCode::RepoFileTemplate.expects(:new).with(
          @repo,
          ConfigAsCode::RepoFileTemplate::COMMAND_CONFIG,
          validator_class: SlashCommands::Validator,
          oid: "fake_oid"
        )

        repo_file_template = ConfigAsCode::RepoFileTemplate.for_path(
          @repo, ConfigAsCode::RepoFileTemplate::COMMAND_CONFIG + "/status.yml", @repo.owner, oid: "fake_oid"
        )
      end
    end

    context "when structured_issue_comment_templates is enabled" do
      test "returns the repo file template for the given path" do
        repo_file_template = ConfigAsCode::RepoFileTemplate.for_path(
          @repo, ConfigAsCode::RepoFileTemplate::ISSUE_COMMENT_TEMPLATE + "/status.yml", @repo.owner
        )
        refute_nil repo_file_template
        assert_equal UI::FormSchema::TemplateValidator, repo_file_template.validator_class
      end

      test "passes oid along" do
        ConfigAsCode::RepoFileTemplate.expects(:new).with(
          @repo,
          ConfigAsCode::RepoFileTemplate::ISSUE_COMMENT_TEMPLATE,
          validator_class: UI::FormSchema::TemplateValidator,
          oid: "fake_oid"
        )

        repo_file_template = ConfigAsCode::RepoFileTemplate.for_path(
          @repo, ConfigAsCode::RepoFileTemplate::ISSUE_COMMENT_TEMPLATE + "/status.yml", @repo.owner, oid: "fake_oid"
        )
      end
    end
  end

  context "#yaml_templates" do
    test "gets all the yaml files for a given repo/path" do
      commit = @repo.commits.create({ message: "Add structured template", author: @repo.owner }) do |files|
        files.add "#{ConfigAsCode::RepoFileTemplate::ISSUE_COMMENT_TEMPLATE}/funtimes_1.yml", @funtimes_yaml
        files.add "#{ConfigAsCode::RepoFileTemplate::ISSUE_COMMENT_TEMPLATE}/funtimes_2.yml", @funtimes_yaml
        files.add "#{ConfigAsCode::RepoFileTemplate::ISSUE_COMMENT_TEMPLATE}/funtimes_3.yml", @funtimes_yaml
        files.add "#{ConfigAsCode::RepoFileTemplate::ISSUE_COMMENT_TEMPLATE}/funtimes_4.yml", @funtimes_yaml
      end
      @repo.refs["refs/heads/master"].update(commit, @repo.owner)


      templates = ConfigAsCode::RepoFileTemplate.new(
        @repo,
        ConfigAsCode::RepoFileTemplate::ISSUE_COMMENT_TEMPLATE,
        validator_class: UI::FormSchema::TemplateValidator
      )

      assert_equal(
        [
          "funtimes_1.yml",
          "funtimes_2.yml",
          "funtimes_3.yml",
          "funtimes_4.yml",
        ],
        templates.yaml_templates.map(&:filename)
      )
    end
  end

  def commit_file(repo, message, path, filename, contents)
    commit = repo.commits.create({ message: message, author: @repo.owner }) do |files|
      files.add "#{path}/#{filename}", contents
    end
    @repo.refs["refs/heads/master"].update(commit, @repo.owner)

    directory = @repo.directory(@repo.default_oid, path)
    directory.tree_entries.first
  end
end
