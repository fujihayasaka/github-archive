# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class UserDefinedCommandTest < GitHub::TestCase
    include GitHub::UserDefinedCommandTestHelpers

    fixtures do
      add_file_to_commands("fill_from_template.yml", <<~YAML)
        ---
        trigger: fill_from_template
        title: "Fill from template"
        surfaces:
          - issue
        steps:
          - type: fill
            template_path: .github/commands/template.liquid
      YAML

      add_file_to_commands("template.liquid", <<~YAML)
        Hi, {{ data.first}} {{ data.last }}!
      YAML

      add_file_to_commands("table.yml", <<~YAML)
        ---
        trigger: my_table
        title: "My table"
        description: "Insert a markdown table"
        surfaces: pull_request
        steps:
          - type: menu
            id: rows
            label: My rows
            options:
              - text: 1 row
                value: 1
                description: Some description for row 1
              - text: 2 rows
                value: 2
                description: Some description for row 2
          - type: menu
            id: columns
            label: My columns
            options:
              - text: 1 column
                value: 1
              - text: 2 columns
                value: 2
          - type: fill
            template: You get a table with {{ data.rows }} rows and {{ data.columns }} columns.
      YAML

      add_file_to_commands("specialMerge.yml", <<~YAML)
        ---
        trigger: my_merge
        title: "My merge"
        description: "Run a special merge workflow"
        steps:
          - type: form
            style: embedded
            body:
              - type: input
                attributes:
                  label: Version
                  format: text
              - type: textarea
                attributes:
                  label: Release notes
                  placeholder: What changed?
            actions:
              submit: create
              cancel: close
          - type: repository_dispatch
            eventType: specialMerge
      YAML

      add_file_to_commands("shortcut.yml", <<~YAML)
        ---
        trigger: shortcut
        title: "Shortcut"
        description: "Run a special merge workflow"
        steps:
          - type: flash
            template: Hi there.
      YAML

      add_file_to_commands("invalid.yml", <<~YAML)
        ---
        trigger: invalid
        title: "Invalid steps"
        steps:
          - type: form
            body:
              - type: input
                attributes:
                  label: Version
                  format: text
          - type: someInvalidStep
      YAML

      add_file_to_commands("bad_repository_dispatch.yml", <<~YAML)
        ---
        trigger: bad_repository_dispatch
        title: bad repo dispatch
        steps:
          - type: repository_dispatch
      YAML


      add_file_to_commands("fill_with_submit_form.yml", <<~YAML)
        ---
        trigger: fill_with_submit_form
        title: "Fill with submit form"
        surfaces:
          - issue
        steps:
          - type: fill
            submit_form: true
            template_path: .github/commands/template.liquid
      YAML

      # Using Ruby hash to programmatically generate many steps
      too_many_steps = {
        "trigger" => "too_many_steps",
        "title" => "too_many_steps",
        "steps" => 26.times.map do
          { "type" => "actions", "event" => "repository_dispatch" }
        end
      }
      add_file_to_commands("too_many_steps.yml", too_many_steps.to_yaml)
    end

    test "commands with too many steps aren't enabled" do
      command = build_user_defined_command("too_many_steps", surface: :issue)

      assert_equal command.pages, [UserDefinedCommand::COMMAND_NOT_FOUND_PAGE]
    end

    context "triggers" do
      test "lists user-defined commands for the pull_request surface" do
        pr_context = build_command_context(
          current_repository: @repo,
          current_user: @owner,
          surface: :pull_request
        )

        triggers = UserDefinedCommand.triggers(pr_context)

        refute_includes triggers.map(&:name), "fill_from_template"
      end

      test "lists user-defined commands for the issue surface" do
        issue_context = build_command_context(
          current_repository: @repo,
          subject: @issue,
          current_user: @owner
        )

        triggers = UserDefinedCommand.triggers(issue_context)


        refute_includes triggers.map(&:name), "table"
      end

      test "lists user-defined commands for the discussion surface" do
        discussion_context = build_command_context(
          current_repository: @repo,
          current_user: @owner,
          surface: :discussion
        )

        triggers = UserDefinedCommand.triggers(discussion_context)

        refute_includes triggers.map(&:name), "table"
        refute_includes triggers.map(&:name), "fill_from_template"
      end

      test "public repositories list no user defined commands", skip_enterprise: true do
        perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @repo.toggle_visibility(actor: @owner, visibility: "public") }
        assert @repo.reload.public?, "Expected repository to be public"

        issue_context = build_command_context(
          current_repository: @repo,
          subject: @issue,
          current_user: @owner
        )

        triggers = UserDefinedCommand.triggers(issue_context)

        assert_equal triggers, []
      end
    end

    test "invalid step types" do
      command = build_user_defined_command("invalid")
      command.process

      assert_equal command.flash.error, "Command contains invalid step type: someInvalidStep"
    end

    test "interprets GitHub Shortcut steps as invalid when feature flag turned off" do
      disable_feature_flag(:shortcuts)

      command = build_user_defined_command("shortcut")
      command.process

      assert_equal command.flash.error, "Command contains invalid step type: flash"
    end

    context "template data" do
      test "includes information about the subject" do
        command = build_user_defined_command("my_table", surface: :issue, subject: @issue)

        expected_resource = {
          "type" => "Issue",
          "id" => @issue.global_relay_id,
          "number" => @issue.number
        }

        assert_equal expected_resource, command.template_data.dig("command", "resource")
      end

      test "includes information about the repository where the command ran" do
        command = build_user_defined_command("my_table", surface: :issue, subject: @issue)

        expected_repository = {
          "full_name" => @repo.nwo,
          "node_id" => @repo.global_relay_id,
          "clone_url" => @repo.clone_url
        }

        assert_equal expected_repository, command.template_data.dig("command", "repository")
      end
    end

    context "/my_table" do
      test "first page displays row menu" do
        command = build_user_defined_command("my_table", surface: :pull_request)

        assert_command_rendered(command, name: "rows", breadcrumbs: ["Test", "My rows"], count: 2) do |menu_items|
          assert_same_elements ["1 row", "2 rows"], menu_items.map(&:text)
          assert_same_elements [1, 2], menu_items.map(&:value)
          assert_same_elements ["Some description for row 1", "Some description for row 2"], menu_items.map(&:description)
        end
      end

      test "second page displays column menu" do
        command = build_user_defined_command("my_table", surface: :pull_request, page_number: 2)

        assert_command_rendered(command, name: "columns", breadcrumbs: ["Test", "My rows", "My columns"], count: 2) do |menu_items|
          assert_same_elements ["1 column", "2 columns"], menu_items.map(&:text)
          assert_same_elements [1, 2], menu_items.map(&:value)
          assert_same_elements [nil, nil], menu_items.map(&:description)
        end
      end

      test "fills item when selected" do
        command = build_user_defined_command("my_table", surface: :pull_request, page_number: 3, data: { rows: 3, columns: 2 })

        assert_command_fill(command, "You get a table with 3 rows and 2 columns.")
      end

      test "doesn't work on the issue" do
        command = build_user_defined_command("my_table", surface: :issue)
        command.process

        assert_equal command.flash.error, "Command not found"
      end
    end

    context "/fill_from_template" do
      test "/fill_from_template only works on issues, not discussions" do
        assert_command_fill(
          build_user_defined_command("fill_from_template", surface: :issue),
          "Hi"
        )

        discussion_command = build_user_defined_command("fill_from_template", surface: :discussion)
        discussion_command.process

        assert_equal discussion_command.flash.error, "Command not found"
      end

      test "renders liquid template from repository" do
        command = build_user_defined_command("fill_from_template", data: { first: "Frank", last: "Jones" })

        assert_command_fill(command, "Hi, Frank Jones!")
      end

      test "doesn't work on a public repository", skip_enterprise: true do
        perform_enqueued_jobs(only: RepositoryOrchestrationJob) { @repo.toggle_visibility(actor: @owner, visibility: "public") }
        assert @repo.reload.public?, "Expected repository to be public"

        command = build_user_defined_command("fill_from_template", surface: :issue)
        command.process

        assert_equal command.flash.error, "Command not found"
      end
    end

    context "/fill_with_submit_form" do
      test "/fill_with_submit_form only works on issues, not discussions" do
        command = build_user_defined_command("fill_with_submit_form", surface: :issue)

        assert_command_fill(
          command,
          "Hi"
        )

        assert_equal true, command.page.submit_form
      end
    end

    context "/my_merge" do
      test "first page renders a form" do
        command = build_user_defined_command("my_merge", surface: :pull_request)

        render_inline(command, allowed_queries: 1)
        assert_text_field("Version")
        assert_text_area("Release notes")
        assert_submit_action("create")
        assert_close_action("close")
      end

      test "second page triggers a repository dispatch" do
        command = build_user_defined_command("my_merge", surface: :pull_request, page_number: 2, data: { version: "1.2" })

        @repo.expects(:dispatch_event).with(
          @owner.id,
          "specialMerge",
          command.template_data,
        )

        command.process

        assert_equal command.flash.notice, "Triggering a `specialMerge` repository dispatch event"
      end

      test "second page displays error when user can't write to repository" do
        other_user = create(:user)
        @repo.add_member(other_user, action: :read)
        assert @repo.readable_by?(other_user), "Expected other_user to be able to see repository"

        command = build_user_defined_command("my_merge", surface: :pull_request, page_number: 2, current_user: other_user)

        @repo.expects(:dispatch_event).never
        command.process

        assert_match /You must have push access to the repository/, command.flash.error
      end
    end

    context "/bad_repository_dispatch" do
      test "displays a flash error" do
        command = build_user_defined_command("bad_repository_dispatch")

        command.process

        assert_match /`eventType` property not set/, command.flash.error
      end
    end
  end
end
