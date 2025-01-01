# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class StructuredIssueCommentCommandTest < GitHub::TestCase
    include GitHub::ComponentTestHelpers
    include GitHub::SlashCommandTestHelpers
    include HydroTestHelpers

    BUGS_YAML = <<~YML
      name: Bug Template
      description: It's a bug
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

    FUNTIMES_YAML = <<~YML
      name: Fun Times
      description: It's a party
      body:
        - title: Party time?
          type: Input.Toggle
          id: repro
      YML

    fixtures do
      @repo = create(:repository)
      @issue = create(:issue, repository: @repo)
    end

    setup do
      example_repo :dot_github, @repo
      @context = build_command_context(current_repository: @repo, subject: @issue)
      enable_feature_flag(:structured_issue_comment_templates, @repo)
    end

    def add_repo_templates
      commit = @repo.commits.create({ message: "Add structured template", author: @repo.owner }) do |files|
        files.add "#{ConfigAsCode::RepoFileTemplate::ISSUE_COMMENT_TEMPLATE}/funtimes.yml", FUNTIMES_YAML
        files.add "#{ConfigAsCode::RepoFileTemplate::ISSUE_COMMENT_TEMPLATE}/bugs.yml", BUGS_YAML
      end
      @repo.refs["refs/heads/master"].update(commit, @repo.owner)
    end

    context "enabled?" do
      test "doesnt show when not enabled" do
        disable_feature_flag(:structured_issue_comment_templates)
        refute SlashCommands::StructuredIssueCommentCommand.enabled?(@context)
      end

      test "doesnt show when enabled and no templates" do
        refute SlashCommands::StructuredIssueCommentCommand.enabled?(@context)
      end

      test "does show when enabled and there are templates" do
        add_repo_templates
        assert SlashCommands::StructuredIssueCommentCommand.enabled?(@context)
      end

      test "displays all the templates" do
        add_repo_templates
        triggers = SlashCommands::StructuredIssueCommentCommand.triggers(@context)

        assert_equal 2, triggers.size

        assert_equal "comment-template-bugs-yml", triggers[0].name
        assert_equal "bugs.yml", triggers[0].value
        assert_equal "It's a bug", triggers[0].description

        assert_equal "comment-template-funtimes-yml", triggers[1].name
        assert_equal "funtimes.yml", triggers[1].value
        assert_equal "It's a party", triggers[1].description
      end

      test "renders form" do
        add_repo_templates

        command = build_command(
          SlashCommands::StructuredIssueCommentCommand,
          current_repository: @repo,
          trigger_name: "comment-template-bugs-yml",
          trigger_value: "bugs.yml"
        )

        render_inline(command)
        assert_selector("form")
        assert_selector("input[name='command[Operating System]']")
      end

      test "flashes with missing template" do
        add_repo_templates

        command = build_command(
          SlashCommands::StructuredIssueCommentCommand,
          current_repository: @repo,
          trigger_name: "comment-template-foo-yml",
          trigger_value: "foo.yml"
        )

        command.process
        assert_equal("Invalid option chosen", command.flash.error)
      end

      test "renders invalid template" do
        add_repo_templates

        command = build_command(
          SlashCommands::StructuredIssueCommentCommand,
          current_repository: @repo,
          trigger_name: "comment-template-funtimes-yml",
          trigger_value: "funtimes.yml"
        )

        command.process
        render_inline(command)
        assert_selector("form")
        assert_selector("[data-test-selector='errors']")
      end

      test "submits a hydro meta data blob event" do
        enable_feature_flag(:meta_data_blobs)

        data = ActionController::Parameters.new(
          "label.repo": "Reproducemepls",
          "repo": "Tacos are delicious",
        )

        parent = create(:issue, repository: @repo)
        user = create(:user)
        command = build_command(
          SlashCommands::StructuredIssueCommentCommand,
          current_repository: @repo,
          current_user: user,
          trigger_name: "comment-template-bugs-yml",
          trigger_value: "bugs.yml",
          data: data,
          subject: parent,
        )

        command.submit_comment

        comment = parent.comments.last

        expected_hydro_payload = {
          action: "CREATED",
          actor_id: user.id,
          data: JSON.dump(data.to_unsafe_h),
          parent_id: comment.id,
          parent_type: comment.class.to_s,
          submitter_id: "SlashCommands::StructuredIssueCommentCommand",
          submitter_type: "slash_command"
        }
        assert_hydro_published(expected_hydro_payload, schema: "github.v1.MetaDataBlobEvent")
        assert_hydro_messages(count: 1, schema: "github.v1.MetaDataBlobEvent")
      end

      test "does not submit a hydro meta data blob event when flipper is off" do
        # this is the key :point_down:
        disable_feature_flag(:meta_data_blobs)

        data = ActionController::Parameters.new(
          "label.repo": "Reproducemepls",
          "repo": "Tacos are delicious",
        )

        parent = create(:issue, repository: @repo)
        command = build_command(
          SlashCommands::StructuredIssueCommentCommand,
          current_repository: @repo,
          trigger_name: "comment-template-bugs-yml",
          trigger_value: "bugs.yml",
          data: data,
          subject: parent,
        )

        command.submit_comment

        assert_hydro_messages(count: 0, schema: "github.v1.MetaDataBlobEvent")
      end
    end
  end
end
