# typed: true
# frozen_string_literal: true

require "test_helper"

class SecuritySettingsStepTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, id: 111)
    @params = { "vulnerability-alerts" => true, "automated-security-fixes" => true }
    @step_obj =  ("StacksSteps::SecuritySettingsStep").constantize
  end

  context "#validate_inputs" do
    test "raises error when dependabot alert not enabled" do
      GitHub.stubs(:enterprise?).returns(false) # rubocop:todo GitHub/DontStubEnterpriseInTests
      GitHub.stubs(:dependabot_enabled?).returns(false)

      error = assert_raises(Errors::SecurityParameterError) do
        @step_obj.validate_inputs(@params, repo: @repo, actor: @user)
      end
      assert_match "Step validation failed: Cannot enable Automated Security Fixes. Dependabot needs to be enabled.", error.message
    end

    test "raises error for GitHub Enterprise" do
      GitHub.stubs(:enterprise?).returns(true) # rubocop:todo GitHub/DontStubEnterpriseInTests
      GitHub.stubs(:dependabot_enabled?).returns(true)

      error = assert_raises(Errors::SecurityParameterError) do
        @step_obj.validate_inputs(@params, repo: @repo, actor: @user)
      end
      assert_match "Step validation failed: Cannot enable Vulnerability Alerts. Unavailable in GitHub enterprise.", error.message
    end

    test "raises error when dependabot alert is enabled without vulnerability" do
      @params = { "vulnerability-alerts" => false, "automated-security-fixes" => true }

      GitHub.stubs(:enterprise?).returns(false) # rubocop:todo GitHub/DontStubEnterpriseInTests
      GitHub.stubs(:dependabot_enabled?).returns(true)

      error = assert_raises(Errors::SecurityParameterError) do
        @step_obj.validate_inputs(@params, repo: @repo, actor: @user)
      end
      assert_match "Step validation failed: Cannot enable Automated Security Fixes. Vulnerability Alerts needs to be true.", error.message
    end
  end

  context "#run:" do
    test "update vulnerability alerts in repository" do
      @params = { "vulnerability-alerts" => true, "automated-security-fixes" => false }

      @repo.stubs(:vulnerability_alerts_enabled?).returns(true)
      @repo.expects(:force_enable_vulnerability_alerts)

      StacksSteps::SecuritySettingsStep.new(instance_id: 123, inputs: @params).run(repo: @repo, actor: @user)
    end

    test "raises error when update vulnerability alerts in repository fails" do
      @params = { "vulnerability-alerts" => true, "automated-security-fixes" => false }

      @repo.stubs(:force_enable_vulnerability_alerts)
      @repo.stubs(:vulnerability_alerts_enabled?).returns(false)

      error = assert_raises(Errors::SecuritySettingsError) do
        StacksSteps::SecuritySettingsStep.new(instance_id: 123, inputs: @params).run(repo: @repo, actor: @user)
      end
      assert_match "Could not enable Vulnerability Alerts.", error.message
    end

    test "update automated fixes in repository" do
      @params = { "vulnerability-alerts" => false, "automated-security-fixes" => true }

      @repo.stubs(:vulnerability_updates_enabled?).returns(true)
      @repo.expects(:enable_vulnerability_updates)

      StacksSteps::SecuritySettingsStep.new(instance_id: 123, inputs: @params).run(repo: @repo, actor: @user)
    end

    test "raises error when update automated fixes in repository fails" do
      @params = { "vulnerability-alerts" => false, "automated-security-fixes" => true }

      @repo.stubs(:enable_vulnerability_updates)
      @repo.stubs(:vulnerability_updates_enabled?).returns(false)

      error = assert_raises(Errors::SecuritySettingsError) do
        StacksSteps::SecuritySettingsStep.new(instance_id: 123, inputs: @params).run(repo: @repo, actor: @user)
      end
      assert_match "Step execution failed: Could not enable Automated Security Fixes.", error.message
    end
  end

  context "cleanup" do
    test "disable the alerts while cleaning up" do
      @repo.force_enable_vulnerability_alerts(actor: @user)
      @repo.enable_vulnerability_updates(actor: @user)

      StacksSteps::SecuritySettingsStep.new(instance_id: 123, inputs: {}).cleanup(repo: @repo, actor: @user)

      assert_equal false, @repo.vulnerability_alerts_enabled?
      assert_equal false, @repo.vulnerability_updates_enabled?
    end
  end
end
