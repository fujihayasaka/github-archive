# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class WorkflowCommandTest < GitHub::TestCase
    include GitHub::ComponentTestHelpers
    include GitHub::SlashCommandTestHelpers

    fixtures do
      @owner = create :user, login: "monalisa"
      @branch = "cr-line-endings"
      @repo = create :repository, owner: @owner, from_example: :simple

      commit_metadata = { committer: @repo.owner, message: "Updating a file" }

      ref = @repo.heads.find_or_build(@repo.default_branch)
      ref.append_commit(commit_metadata, @repo.owner) do |files|
        files.add(".github/workflows/on-push.yml", <<~YAML
          on: [push]
          YAML
        )
        files.add(".github/workflows/on-workflow-dispatch.yml", <<~YAML
          on: workflow_dispatch
          YAML
        )
        files.add(".github/workflows/on-wd-inputs.yml", <<~YAML
          on:
            workflow_dispatch:
              inputs:
                name:
                  default: 'monalisa'
                numOctoCats:
                  required: true
                  description: 'Number of Octocats'
                  default: '1'
          YAML
        )

        files.add(".github/workflows/branch-adds-inputs.yml", <<~YAML)
          on: workflow_dispatch
        YAML

        files.add(".github/workflows/branch-modifies-inputs.yml", <<~YAML)
          on:
            workflow_dispatch:
              inputs:
                not_on_branch:
                  default: 'monalisa'
        YAML
      end

      @repo.heads.find_or_build(@branch).append_commit(commit_metadata, @repo.owner) do |files|
        files.add(".github/workflows/on-workflow-dispatch.yml", <<~YAML)
          on: workflow_dispatch
        YAML

        files.add(".github/workflows/branch-adds-inputs.yml", <<~YAML)
          on:
            workflow_dispatch:
              inputs:
                branch_name:
        YAML

        files.add(".github/workflows/branch-modifies-inputs.yml", <<~YAML)
          on:
            workflow_dispatch:
              inputs:
                branch_name:
        YAML

        files.add(".github/workflows/on-wd-inputs.yml", <<~YAML)
          on: workflow_dispatch
        YAML
      end

      @pull_request = create(
        :pull_request,
        repository: @repo,
        base_repository: @repo,
        head_repository: @repo,
        head_ref: @branch
      )
    end

    setup do
      enable_feature_flag(:workflow_command)
    end

    context ".enabled?" do
      test "only enabled for users who can write to repository", skip_enterprise: true do
        user2 = create(:user)

        owner_context = build_command_context(current_repository: @repo, current_user: @owner, subject: @pull_request)
        user2_context = build_command_context(current_repository: @repo, current_user: user2, subject: @pull_request)

        assert WorkflowCommand.enabled?(owner_context)
        refute WorkflowCommand.enabled?(user2_context)
      end

      test "only enabled when feature flag enabled", skip_enterprise: true do
        disable_feature_flag(:workflow_command)

        context = build_command_context(current_repository: @repo, current_user: @owner, subject: @pull_request)

        assert_changes -> { WorkflowCommand.enabled?(context) }, from: false, to: true do
          enable_feature_flag(:workflow_command)
        end
      end
    end

    context ".triggers" do
      test "trigger description changes depending on subject type" do
        issue_context = build_command_context(current_repository: @repo, current_user: @owner, subject: create(:issue))
        pull_context = build_command_context(current_repository: @repo, current_user: @owner, subject: @pull_request)

        issue_trigger = WorkflowCommand.triggers(issue_context).first
        pull_trigger = WorkflowCommand.triggers(pull_context).first

        refute_match /for this pull request/, issue_trigger.description
        assert_match /for this pull request/, pull_trigger.description
      end
    end

    context "first page" do
      test "lists workflows with on: workflow_dispatch" do
        create(:workflow, repository: @repo, path: ".github/workflows/on-push.yml")
        workflow = create(:workflow, repository: @repo, path: ".github/workflows/on-workflow-dispatch.yml")

        command = build_command(WorkflowCommand, current_repository: @repo)

        assert_command_rendered(command, count: 1) do |items|
          assert_equal workflow.name, items.first.text
          assert_equal ".github/workflows/on-workflow-dispatch.yml", items.first.value
          assert_nil items.first.description
        end
      end

      test "only includes active workflows" do
        create(:workflow, repository: @repo, path: ".github/workflows/on-push.yml", state: :disabled_manually)
        create(:workflow, repository: @repo, path: ".github/workflows/on-workflow-dispatch.yml", state: :deleted)

        command = build_command(WorkflowCommand, current_repository: @repo)

        assert_command_blankslate(command, title: "No workflows found")
      end
    end

    context "second page" do
      test "triggers workflow dispatch for workflow without inputs" do
        workflow_path = ".github/workflows/on-workflow-dispatch.yml"
        workflow = create(:workflow, repository: @repo, path: workflow_path)

        command = build_command(
          WorkflowCommand,
          current_user: @owner,
          current_repository: @repo,
          page_number: 2,
          data: { workflow_path: workflow_path }
        )

        @repo.expects(:dispatch_workflow_event).with(
          @owner.id,
          workflow_path,
          "master",
          nil
        )

        command.process
        assert_equal command.page.type, :action
        assert_equal command.flash.notice, "#{workflow.name} workflow run was successfully requested."
      end

      test "on pull request" do
        workflow_path = ".github/workflows/on-workflow-dispatch.yml"
        workflow = create(:workflow, repository: @repo, path: workflow_path)

        command = build_command(
          WorkflowCommand,
          current_user: @owner,
          current_repository: @repo,
          subject: @pull_request,
          page_number: 2,
          data: { workflow_path: workflow_path }
        )

        @repo.expects(:dispatch_workflow_event).with(
          @owner.id,
          workflow_path,
          @branch,
          nil
        )

        command.process
      end

      test "workflow path doesn't exist within repository" do
        workflow_path = ".github/workflows/on-workflow-dispatch.yml"
        some_other_repo = create(:repository)
        create(:workflow, repository: some_other_repo, path: workflow_path)

        command = build_command(
          WorkflowCommand,
          current_user: @owner,
          current_repository: @repo,
          page_number: 2,
          data: { workflow_path: workflow_path }
        )

        command.process

        assert_equal command.page.type, :action
        assert_equal command.flash.error, "Workflow not found."
      end

      context "with inputs" do
        test "displays inputs" do
          create(:workflow, repository: @repo, path: ".github/workflows/on-wd-inputs.yml")

          command = build_command(WorkflowCommand, current_repository: @repo, page_number: 2, data: { workflow_path: ".github/workflows/on-wd-inputs.yml" })

          render_inline(command, allowed_queries: 1)

          assert_text_field(:name, label: "Name")
          assert_text_field(:numOctoCats, label: "Number of Octocats")
        end

        context "on pull request" do
          test "adding inputs" do
            workflow_path = ".github/workflows/branch-adds-inputs.yml"
            workflow = create(:workflow, repository: @repo, path: workflow_path)

            command = build_command(
              WorkflowCommand,
              current_user: @owner,
              current_repository: @repo,
              subject: @pull_request,
              page_number: 2,
              data: { workflow_path: workflow_path }
            )

            @repo.expects(:dispatch_workflow_event).never

            render_inline(command, allowed_queries: 1)

            assert_text_field(:branch_name)
          end

          test "modifying inputs" do
            workflow_path = ".github/workflows/branch-modifies-inputs.yml"
            workflow = create(:workflow, repository: @repo, path: workflow_path)
            command = build_command(
              WorkflowCommand,
              current_user: @owner,
              current_repository: @repo,
              subject: @pull_request,
              page_number: 2,
              data: { workflow_path: workflow_path }
            )

            @repo.expects(:dispatch_workflow_event).never

            render_inline(command, allowed_queries: 1)

            assert_text_field(:branch_name)
          end

          test "removing inputs" do
            workflow_path = ".github/workflows/on-wd-inputs.yml"
            workflow = create(:workflow, repository: @repo, path: workflow_path)

            command = build_command(
              WorkflowCommand,
              current_user: @owner,
              current_repository: @repo,
              subject: @pull_request,
              page_number: 2,
              data: { workflow_path: workflow_path }
            )

            @repo.expects(:dispatch_workflow_event).with(
              @owner.id,
              workflow_path,
              @branch,
              nil, # Inputs are nil
            )

            command.process

            assert_equal command.page.type, :action
            assert_equal command.flash.notice, "#{workflow.name} workflow run was successfully requested."
          end
        end
      end
    end

    context "third page" do
      test "third page triggers workflow dispatch with processed inputs" do
        workflow_path = ".github/workflows/on-wd-inputs.yml"
        workflow = create(:workflow, repository: @repo, path: workflow_path)

        command = build_command(
          WorkflowCommand,
          current_user: @owner,
          current_repository: @repo,
          page_number: 3,
          data: { name: "Foo bar", workflow_path: workflow_path }
        )

        @repo.expects(:dispatch_workflow_event).with(
          @owner.id,
          workflow_path,
          "master",
          { "name" => "Foo bar", "numOctoCats" => "1" }
        )

        command.process

        assert_equal command.page.type, :action
        assert_equal command.flash.notice, "#{workflow.name} workflow run was successfully requested."
      end

      test "third page shows error when unexpected input is provided" do
        workflow_path = ".github/workflows/on-wd-inputs.yml"
        workflow = create(:workflow, repository: @repo, path: workflow_path)

        command = build_command(
          WorkflowCommand,
          current_user: @owner,
          current_repository: @repo,
          page_number: 3,
          data: { unexpected: "Foo bar", workflow_path: workflow_path }
        )

        @repo.expects(:dispatch_workflow_event).never

        command.process

        assert_equal command.page.type, :action
        assert_match /Unexpected input/, command.flash.error
      end
    end
  end
end
