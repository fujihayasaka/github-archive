# typed: false
# frozen_string_literal: true

require "test_helper"

class CreateEnvironmentStepTest < GitHub::TestCase
  fixtures do
    make_trusted_oauth_apps_owner

    @user = create(:user)
    @repo = create(:repository, owner: @user, id: 111)
    @step_obj = ("StacksSteps::CreateEnvironmentStep").constantize
    @actions_app = create :launch_integration
    @installation = make_integration_installation integration: @actions_app, target: @repo.owner
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
  end

  context "#validate_inputs:" do
    test "raises error on name length exceeding limit" do
      error = assert_raises Errors::ValidationError do
        @step_obj.validate_inputs({ "name" => "s" * 256 }, repo: @repo, actor: @user)
      end
      assert_match "Step validation failed: Environment name length should not be longer than 255", error.message
    end

    test "raises error too many reviewers" do
      error = assert_raises Errors::ValidationError do
        @step_obj.validate_inputs({ "name" => "s", "reviewers" => [1] * (Gate::MAX_APPROVERS + 1) }, repo: @repo, actor: @user)
      end
      assert_match "Step validation failed: reviewers count not exceeds max of 6 for environment s", error.message
    end

    test "raises error on exceeding max timer" do
      params = { "name" => "staging", "wait-timer" => 43210 }

      error = assert_raises Errors::ValidationError do
        @step_obj.validate_inputs(params, repo: @repo, actor: @user)
      end
      assert_match "wait-timer for environment #{params["name"]} config should be between 0 - #{Gate::MAX_TIMEOUT_MINUTES}", error.message
    end

    test "raises error when inputs has both branch policies" do
      params = { "name" => "staging", "allowed-branch-rules" => ["main/*", "releases/*"], "protected-branches" => true }

      assert_raises do
        @step_obj.validate_inputs(params, repo: @repo, actor: @user)
      end
    end
  end

  context "#run:" do
    test "create an environment with given name" do
      params = { "name" => "staging" }

      StacksSteps::CreateEnvironmentStep.new(instance_id: 123, inputs: params).run(repo: @repo, actor: @user)

      env = Environment.find_by(name: "staging")
      refute_nil env
    end

    test "create environment with wait timer" do
      params = { "name" => "staging", "wait-timer" => 43 }
      StacksSteps::CreateEnvironmentStep.new(instance_id: 123, inputs: params).run(repo: @repo, actor: @user)

      env = Environment.find_by(name: "staging")
      refute_nil env
      refute_nil env.gates
      assert_equal 1, env.gates.size
      assert_equal "timeout", env.gates[0].type
    end

    test "create environment with reviewers" do
      params = { "name" => "staging", "reviewers" => [{ "type" => "User", "name" => @user.name }] }

      StacksSteps::CreateEnvironmentStep.new(instance_id: 123, inputs: params).run(repo: @repo, actor: @user)

      env = Environment.find_by(name: "staging")
      refute_nil env
      refute_nil env.gates
      assert_equal 1, env.gates.size
      assert_equal "manual_approval", env.gates[0].type
      assert_equal 1, env.gates[0].gate_approvers.size
    end

    test "remove reviewers from environment" do
      params = { "name" => "staging", "reviewers" => {} }

      Environment.any_instance.expects(:remove_approval_gate)

      StacksSteps::CreateEnvironmentStep.new(instance_id: 123, inputs: params).run(repo: @repo, actor: @user)
    end

    unless GitHub.enterprise?
      test "create environment with branch policy gate - only protected branches" do
        params = { "name" => "staging", "protected-branches" => "true" }

        StacksSteps::CreateEnvironmentStep.new(instance_id: 123, inputs: params).run(repo: @repo, actor: @user)

        env = Environment.find_by(name: "staging")
        refute_nil env
        refute_nil env.gates
        assert_equal 1, env.gates.size
        assert_equal "branch_policy", env.gates[0].type

        gate_body = JSON.parse(env.gates[0].body)
        assert_equal gate_body.dig("protected_branches"), true
      end
    end

    unless GitHub.enterprise?
      test "create environment with branch policy gate - only custom branch policies" do
        params = { "name" => "staging", "allowed-branch-rules" => ["main/*", "releases/*"] }

        StacksSteps::CreateEnvironmentStep.new(instance_id: 123, inputs: params).run(repo: @repo, actor: @user)

        env = Environment.find_by(name: "staging")
        refute_nil env
        refute_nil env.gates
        assert_equal 1, env.gates.size
        assert_equal "branch_policy", env.gates[0].type

        gate_body = JSON.parse(env.gates[0].body)
        assert_equal false, gate_body.dig("protected_branches")

        gate = env.gates[0]
        assert_equal 2, gate.branch_policies.size
      end
    end

    test "create environment with branch policy gate - no branch policies" do
      params = { "name" => "staging" }

      StacksSteps::CreateEnvironmentStep.new(instance_id: 123, inputs: params).run(repo: @repo, actor: @user)

      env = Environment.find_by(name: "staging")
      refute_nil env
      refute_nil env.gates
      assert_equal 0, env.gates.size
    end

    unless GitHub.enterprise?
      test "throw error when environment gets created with both branch policies" do
        params = { "name" => "staging", "allowed-branch-rules" => ["main/*", "releases/*"], "protected-branches" => true }

        assert_raises do
          StacksSteps::CreateEnvironmentStep.new(instance_id: 123, inputs: params).run(repo: @repo, actor: @user)
        end
      end

      test "do not throw error when environment gets created with no protection" do
        params = { "name" => "playground" }

        StacksSteps::CreateEnvironmentStep.new(instance_id: 123, inputs: params).run(repo: @repo, actor: @user)
        env = Environment.find_by(name: "playground")
        refute_nil env
      end

      test "do not throw error when environment gets created with false protected branches no protection and no rules" do
        params = { "name" => "playground", "protected-branches" => false }

        StacksSteps::CreateEnvironmentStep.new(instance_id: 123, inputs: params).run(repo: @repo, actor: @user)
        env = Environment.find_by(name: "playground")
        refute_nil env
      end

      test "do not throw error when environment gets created with false protected branches and empty rules" do
        params = { "name" => "playground", "allowed-branch-rules" => [], "protected-branches" => false }

        StacksSteps::CreateEnvironmentStep.new(instance_id: 123, inputs: params).run(repo: @repo, actor: @user)
        env = Environment.find_by(name: "playground")
        refute_nil env
      end
    end
  end
end
