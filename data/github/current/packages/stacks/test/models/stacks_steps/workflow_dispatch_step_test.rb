# typed: true
# frozen_string_literal: true

require "test_helper"

class WorkflowDispatchStepTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, id: 111)
    @stack_repo = create(:repository, owner: @user, id: 222, from_example: :stacks_repo)
    @step_obj = ("StacksSteps::WorkflowDispatchStep").constantize

    make_trusted_oauth_apps_owner
    launch_app = create(:launch_integration)
    GitHub.stubs(:launch_github_app).returns(launch_app)

    workflow_with_large_inputs_hash = {
      "on" => {
        "workflow_dispatch" => {
          "inputs" => {}
        }
      }
    }

    2200.times do |i|
      input_name = "input-#{i}"
      workflow_with_large_inputs_hash["on"]["workflow_dispatch"]["inputs"][input_name] = {
        "description" => "Test input",
        "required" => false
      }
    end

    workflow_with_large_inputs = workflow_with_large_inputs_hash.to_yaml

    stack_commit_metadata = { committer: @stack_repo.owner, message: "Adding init workflows" }
    stack_ref = @stack_repo.heads.find_or_build(@stack_repo.default_branch)
    stack_ref.append_commit(stack_commit_metadata, @stack_repo.owner) do |files|
      files.add(".github/workflows/init-no-dispatch.yml", <<~YAML
        on: push
        YAML
      )
    end

    commit_metadata = { committer: @repo.owner, message: "Adding init workflows" }
    ref = @repo.heads.find_or_build(@repo.default_branch)
    ref.append_commit(commit_metadata, @repo.owner) do |files|
      files.add(".github/workflows/init.yml", <<~YAML
        on: workflow_dispatch
        YAML
      )
      files.add(".github/workflows/init-with-inputs.yml", <<~YAML
        on:
          workflow_dispatch:
            inputs:
              name:
                description: 'App name'
              env:
                required: true
                description: 'App env'
                default: 'stage'
              sku:
                required: true
                description: 'App SKU'
        YAML
      )
      files.add(".github/workflows/init-with-large-inputs.yml", workflow_with_large_inputs)
    end
    create :release, name: "Version One!", tag_name: "v1.0", author: @stack_repo.owner, repository: @stack_repo
  end

  context "#validate_inputs" do
    test "raises error when cannot find init workflow file" do
      inputs_hash = {
        "workflow_path" => "init-missing.yml",
        "ref"           => "v1.0",
        "stack_inputs_hash" => {}
      }

      error = assert_raises(Errors::ValidationError) do
        @step_obj.validate_inputs(inputs_hash, repo: @repo, actor: @user, stack_repo: @stack_repo)
      end
      assert_match "Step validation failed: Invalid or missing workflow file '.github/workflows/init-missing.yml'.", error.message
    end

    test "raises error when ref is missing" do
      inputs_hash = {
        "workflow_path" => "init-missing.yml",
        "stack_inputs_hash" => {}
      }

      error = assert_raises(Errors::ValidationError) do
        @step_obj.validate_inputs(inputs_hash, repo: @repo, actor: @user, stack_repo: @stack_repo)
      end
      assert_match "Step validation failed: Missing ref to '.github/workflows/init-missing.yml'.", error.message
    end

    test "raises error when ref is invalid" do
      inputs_hash = {
        "workflow_path" => "init-missing.yml",
        "ref"           => 1,
        "stack_inputs_hash" => {}
      }

      error = assert_raises(Errors::ValidationError) do
        @step_obj.validate_inputs(inputs_hash, repo: @repo, actor: @user, stack_repo: @stack_repo)
      end
      assert_match "Step validation failed: Invalid clone ref to '.github/workflows/init-missing.yml'.", error.message
    end

    test "raises error when no workflow_dispatch trigger found" do
      inputs_hash = {
        "workflow_path" => "init-no-dispatch.yml",
        "ref"           => "v1.0",
        "stack_inputs_hash" => {}
      }

      error = assert_raises(Errors::ValidationError) do
        @step_obj.validate_inputs(inputs_hash, repo: @repo, actor: @user, stack_repo: @stack_repo)
      end
      assert_match "Step validation failed: No workflow_dispatch trigger found in '.github/workflows/init-no-dispatch.yml'.", error.message
    end

    test "raises error when workflow_path is missing" do
      error = assert_raises(Errors::MissingKeyError) do
        @step_obj.validate_inputs({}, repo: @repo, actor: @user, stack_repo: @stack_repo)
      end
      assert_match "Step validation failed: 'workflow_path' key missing in inputs", error.message
    end
  end

  context "#run:" do
    unless GitHub.enterprise?
      test "successfully triggers workflow without any inputs" do
        @repo.expects(:dispatch_workflow_event)

        inputs_hash = {
          "workflow_path" => "init.yml",
          "ref"           => "v1.0",
          "stack_inputs_hash" => {}
        }

        StacksSteps::WorkflowDispatchStep.new(instance_id: 123, inputs: inputs_hash).run(repo: @repo, actor: @user)
      end

      test "successfully maps stack inputs" do
        workflow_path = "init-with-inputs.yml"
        @repo.expects(:dispatch_workflow_event).with(
          @user.id,
          ".github/workflows/#{ workflow_path }",
          "master",
          { "name" => "octo", "env" => "prod", "sku" => "premium" }
        )

        inputs_hash = {
          "workflow_path" => workflow_path,
          "ref"           => "v1.0",
          "stack_inputs_hash" => {
            "name" => { "value": "octo" },
            "env" => { "value": "prod" },
            "sku" => { "value": "premium" }
          }
        }

        StacksSteps::WorkflowDispatchStep.new(instance_id: 123, inputs: inputs_hash).run(repo: @repo, actor: @user)
      end

      test "successfully maps default workflow inputs" do
        workflow_path = "init-with-inputs.yml"
        @repo.expects(:dispatch_workflow_event).with(
          @user.id,
          ".github/workflows/#{ workflow_path }",
          "master",
          { "name" => "octo", "env" => "stage", "sku" => "premium" }
        )

        inputs_hash = {
          "workflow_path" => workflow_path,
          "ref"           => "v1.0",
          "stack_inputs_hash" => {
            "name" => { "value": "octo" },
            "sku" => { "value": "premium" }
          }
        }

        StacksSteps::WorkflowDispatchStep.new(instance_id: 123, inputs: inputs_hash).run(repo: @repo, actor: @user)
      end

      test "raises error when required workflow input is not passed" do
        workflow_path = ".github/workflows/init-with-inputs.yml"

        inputs_hash = {
          "workflow_path" => workflow_path,
          "ref"           => "v1.0",
          "stack_inputs_hash" => {
            "name" => { "value": "octo" },
            "env" => { "value": "prod" }
          }
        }

        error = assert_raises(Errors::WorkflowDispatchError) do
          StacksSteps::WorkflowDispatchStep.new(instance_id: 123, inputs: inputs_hash).run(repo: @repo, actor: @user)
        end
      end

      test "raises error when inputs too large" do
        workflow_path = "init-with-large-inputs.yml"

        inputs_hash = {
          "workflow_path" => workflow_path,
          "ref"           => "v1.0",
          "stack_inputs_hash" => {}
        }

        2200.times do |i|
          input_name = "input-#{i}"
          inputs_hash["stack_inputs_hash"][input_name] = {
            "value": "Test value - #{i}"
          }
        end

        error = assert_raises(Errors::WorkflowDispatchError) do
          StacksSteps::WorkflowDispatchStep.new(instance_id: 123, inputs: inputs_hash).run(repo: @repo, actor: @user)
        end
        assert_match "Step execution failed: Error while triggering workflow dispatch. Error message: Workflow inputs are too large", error.message
      end

      test "raises error when too many inputs" do
        workflow_path = "init-with-large-inputs.yml"

        inputs_hash = {
          "workflow_path" => workflow_path,
          "ref"           => "v1.0",
          "stack_inputs_hash" => {}
        }

        101.times do |i|
          input_name = "input-#{i}"
          inputs_hash["stack_inputs_hash"][input_name] = {
            "value": "Test value - #{i}"
          }
        end

        error = assert_raises(Errors::WorkflowDispatchError) do
          StacksSteps::WorkflowDispatchStep.new(instance_id: 123, inputs: inputs_hash).run(repo: @repo, actor: @user)
        end
        assert_match "Step execution failed: Error while triggering workflow dispatch. Error message: Maximum allowed workflow inputs is #{StacksSteps::WorkflowDispatchStep::WORKFLOW_DISPATCH_INPUT_LIMIT}", error.message
      end

      test "does not pass secrets" do
        workflow_path = "init-with-inputs.yml"
        @repo.expects(:dispatch_workflow_event).with(
          @user.id,
          ".github/workflows/#{ workflow_path }",
          "master",
          { "name" => "octo", "env" => "stage", "sku" => "premium" }
        )

        inputs_hash = {
          "workflow_path" => workflow_path,
          "ref"           => "v1.0",
          "stack_inputs_hash" => {
            "name" => { "value": "octo" },
            "env" => { "value": "prod", "is-secret": true },
            "sku" => { "value": "premium", "is-secret": false }
          }
        }

        StacksSteps::WorkflowDispatchStep.new(instance_id: 123, inputs: inputs_hash).run(repo: @repo, actor: @user)
      end

      test "triggers launch app installation" do
        @repo.expects(:dispatch_workflow_event)
        @repo.expects(:enable_actions_app)

        inputs_hash = {
          "workflow_path" => "init.yml",
          "ref"           => "v1.0",
          "stack_inputs_hash" => {}
        }

        StacksSteps::WorkflowDispatchStep.new(instance_id: 123, inputs: inputs_hash).run(repo: @repo, actor: @user)
      end

      test "does not trigger launch app installation when already installed" do
        @repo.enable_actions_app(entry_point: :test_case)
        @repo.expects(:dispatch_workflow_event)
        @repo.expects(:enable_actions_app).never

        inputs_hash = {
          "workflow_path" => "init.yml",
          "ref"           => "v1.0",
          "stack_inputs_hash" => {}
        }

        StacksSteps::WorkflowDispatchStep.new(instance_id: 123, inputs: inputs_hash).run(repo: @repo, actor: @user)
      end
    end
  end
end
