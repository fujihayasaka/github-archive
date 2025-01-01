# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class IssueTemplatesCommandTest < GitHub::TestCase
    include GitHub::SlashCommandTestHelpers

    fixtures do
      @repo = create(:repository, from_example: :simple)
    end

    setup do
      enable_feature_flag(:slash_commands_templates_command)
    end

    test "displays blankslate when repo has no issue templates" do
      command = build_command(SlashCommands::IssueTemplatesCommand, current_repository: @repo)
      assert_command_blankslate(command, title: "No issue templates", description: /issue templates/)
    end

    test "displays issue templates" do
      create_markdown_templates(count: 3)

      command = build_command(SlashCommands::IssueTemplatesCommand, current_repository: @repo)
      assert_command_rendered(command, count: 3) do |menu_items|
        assert_same_elements ["MD Template 1", "MD Template 2", "MD Template 3"], menu_items.map(&:text)
        assert_same_elements ["test_1.md", "test_2.md", "test_3.md"], menu_items.map(&:value)
      end
    end

    test "only displays up to the limit of issue templates" do
      create_markdown_templates(count: 5)

      SlashCommands::IssueTemplatesCommand.stub_const(:TEMPLATES_LIMIT, 3) do
        command = build_command(SlashCommands::IssueTemplatesCommand, current_repository: @repo)
        assert_command_rendered(command, count: 3) do |menu_items|
          assert_same_elements ["MD Template 1", "MD Template 2", "MD Template 3"], menu_items.map(&:text)
          assert_same_elements ["test_1.md", "test_2.md", "test_3.md"], menu_items.map(&:value)
        end
      end
    end

    test "only displays markdown issue templates" do
      create_markdown_and_yaml_templates(count: 2)

      command = build_command(SlashCommands::IssueTemplatesCommand, current_repository: @repo)
      assert_command_rendered(command, count: 2) do |menu_items|
        assert_same_elements ["MD Template 1", "MD Template 2"], menu_items.map(&:text)
        assert_same_elements ["md_test_1.md", "md_test_2.md"], menu_items.map(&:value)
      end
    end

    test "displays blankslate when only yaml issue templates exist" do
      create_yaml_templates(count: 2)

      command = build_command(SlashCommands::IssueTemplatesCommand, current_repository: @repo)
      assert_command_blankslate(command, title: "No issue templates", description: /issue templates/)
    end

    test "returns the selected template body" do
      create_markdown_templates(count: 2)

      command = build_command(SlashCommands::IssueTemplatesCommand, current_repository: @repo, page_number: 2, data: { template: "test_1.md" })
      assert_command_fill(command, "This is a test template.")
    end

    test "returns the selected template body with encoding" do
      create_markdown_templates(count: 2, prefix: "🐛_test")

      command = build_command(SlashCommands::IssueTemplatesCommand, current_repository: @repo, page_number: 2, data: { template: "🐛_test_1.md" })
      assert_command_fill(command, "This is a test template.")
    end

    test "returns an empty string if the template is not found" do
      create_markdown_templates(count: 2)

      command = build_command(SlashCommands::IssueTemplatesCommand, current_repository: @repo, page_number: 2, data: { template: "test_x.md" })
      assert_command_fill(command, "")
    end

    test "returns an empty string if the template is not specified" do
      create_markdown_templates(count: 2)

      command = build_command(SlashCommands::IssueTemplatesCommand, current_repository: @repo, page_number: 2, data: { template: "" })
      assert_command_fill(command, "")
    end

    private

    def create_markdown_templates(count: 1, prefix: "test")
      commit = @repo.commits.create({ message: "Add markdown templates", committer: @repo.owner }) do |files|
        (1..count).each do |i|
          files.add ".github/ISSUE_TEMPLATE/#{prefix}_#{i}.md", markdown_body(i)
        end
      end

      @repo.refs["refs/heads/master"].update(commit, @repo.owner)
    end

    def create_yaml_templates(count: 1)
      commit = @repo.commits.create({ message: "Add yaml templates", committer: @repo.owner }) do |files|
        (1..count).each do |i|
          files.add ".github/ISSUE_TEMPLATE/test_#{i}.yaml", yaml_body(i)
        end
      end

      @repo.refs["refs/heads/master"].update(commit, @repo.owner)
    end

    def create_markdown_and_yaml_templates(count: 1)
      commit = @repo.commits.create({ message: "Add markdown and yaml templates", committer: @repo.owner }) do |files|
        (1..count).each do |i|
          files.add ".github/ISSUE_TEMPLATE/md_test_#{i}.md", markdown_body(i)
          files.add ".github/ISSUE_TEMPLATE/yaml_test_#{i}.yaml", yaml_body(i)
        end
      end

      @repo.refs["refs/heads/master"].update(commit, @repo.owner)
    end

    def markdown_body(i)
      <<~MARKDOWN
      ---
      name: MD Template #{i}
      about: It's a test template #{i}
      ---
      This is a test template.
      MARKDOWN
    end

    def yaml_body(i)
      <<~YAML
      name: YAML Template #{i}
      description: It's a test template #{i}
      body:
        - type: markdown
          attributes:
            value: |
              This is a test template.
      YAML
    end
  end
end
