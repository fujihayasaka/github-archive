# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class StepBuilder::AddToProjectTest < GitHub::TestCase
    include GitHub::UserDefinedCommandTestHelpers

    fixtures do
      @project = create(:project, name: "My project", owner: @repo)
      @backlog_column = create(:project_column, name: "Backlog", project: @project)
      @in_progress_column = create(:project_column, name: "In progress", project: @project)
    end

    test "adds to in progress column on my project board", temporarily_skip_until_projects_classic_deprecation: true do
      add_file_to_commands("project.yml", <<~YAML)
        ---
        trigger: project
        title: Project
        steps:
        - type: addToProject
          id: myPage
          project: My project
          column: In progress
      YAML

      command = build_user_defined_command("project", subject: @issue)

      command.process

      assert_equal @issue.reload.project_columns, [@in_progress_column]
    end

    test "adds to first column when column not specified", temporarily_skip_until_projects_classic_deprecation: true do
      add_file_to_commands("project.yml", <<~YAML)
        ---
        trigger: project
        title: Project
        steps:
        - type: addToProject
          id: myPage
          project: My project
      YAML

      command = build_user_defined_command("project", subject: @issue)

      command.process

      assert_equal @issue.reload.project_columns, [@backlog_column]
    end

    test "fails when project is closed" do
      add_file_to_commands("project.yml", <<~YAML)
        ---
        trigger: project
        title: Project
        steps:
        - type: addToProject
          id: myPage
          project: My project
      YAML

      command = build_user_defined_command("project", subject: @issue)
      @project.close

      assert_raises(ActiveRecord::RecordNotFound) do
        command.process
      end
    end

    test "fails when project doesn't exist" do
      add_file_to_commands("project.yml", <<~YAML)
        ---
        trigger: project
        title: Project
        steps:
        - type: addToProject
          id: myPage
          project: not a real project name
      YAML

      command = build_user_defined_command("project", subject: @issue)

      assert_raises(ActiveRecord::RecordNotFound) do
        command.process
      end
    end

    test "fails when column doesn't exist" do
      add_file_to_commands("project.yml", <<~YAML)
        ---
        trigger: project
        title: Project
        steps:
        - type: addToProject
          id: myPage
          project: My project
          column: this column doesn't exist
      YAML

      command = build_user_defined_command("project", subject: @issue)

      assert_raises(ActiveRecord::RecordNotFound) do
        command.process
      end
    end
  end
end
