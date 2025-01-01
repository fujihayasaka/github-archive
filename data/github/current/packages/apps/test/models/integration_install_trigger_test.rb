# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationInstallTriggerTest < GitHub::TestCase

  fixtures do
    @app_one = create(:integration, name: "App one")
    @app_two = create(:integration, name: "App two")
  end

  context "install_type" do
    test "only allows defined install_types" do
      assert_raises(ArgumentError) do
        IntegrationInstallTrigger.new(integration: create(:integration), install_type: :some_unknown_type)
      end
    end
  end

  context ".by_install_type scope" do
    test "returns only triggers of the given type" do
      trigger_1 = create(:integration_install_trigger, install_type: :user_created, integration: @app_one)
      trigger_2 = create(:integration_install_trigger, install_type: :file_added, integration: @app_one)
      trigger_3 = create(:integration_install_trigger, install_type: :file_added, integration: @app_two)

      assert_same_elements [trigger_2, trigger_3], IntegrationInstallTrigger.by_install_type(:file_added)
    end

    test "returns only the latest triggers of the given type for an app" do
      trigger_1 = create(:integration_install_trigger, install_type: :file_added, integration: @app_one)
      trigger_2 = create(:integration_install_trigger, install_type: :file_added, integration: @app_two)
      trigger_3 = create(:integration_install_trigger, install_type: :file_added, integration: @app_two)

      assert_same_elements [trigger_1, trigger_3], IntegrationInstallTrigger.by_install_type(:file_added)
    end

    test "does not return any triggers for an app/type when the latest trigger is deactivated" do
      trigger_1 = create(:integration_install_trigger, install_type: :file_added, integration: @app_one)
      trigger_2 = create(:integration_install_trigger, install_type: :file_added, integration: @app_two)
      trigger_3 = create(:integration_install_trigger, install_type: :file_added, integration: @app_two, deactivated: true)

      assert_same_elements [trigger_1], IntegrationInstallTrigger.by_install_type(:file_added)
    end

    test "returns triggers that have been deactivated and reactivated" do
      trigger_1 = create(:integration_install_trigger, install_type: :file_added, integration: @app_one)
      trigger_2 = create(:integration_install_trigger, install_type: :file_added, integration: @app_two)
      trigger_3 = create(:integration_install_trigger, install_type: :file_added, integration: @app_two, deactivated: true)
      trigger_4 = create(:integration_install_trigger, install_type: :file_added, integration: @app_two)

      assert_same_elements [trigger_1, trigger_4], IntegrationInstallTrigger.by_install_type(:file_added)
    end

    test "returns no triggers when an unknown type is passed" do
      trigger_1 = create(:integration_install_trigger, install_type: :file_added, integration: @app_one)
      trigger_2 = create(:integration_install_trigger, install_type: :file_added, integration: @app_two)
      trigger_3 = create(:integration_install_trigger, install_type: :file_added, integration: @app_two)

      assert_predicate IntegrationInstallTrigger.by_install_type(:non_existent), :empty?
    end
  end

  context ".deactivate" do
    test "creates a deactivated record for the given integration/install_type" do
      IntegrationInstallTrigger.deactivate(integration: @app_one, install_type: :file_added)

      assert trigger = IntegrationInstallTrigger.latest(integration: @app_one, install_type: :file_added), "latest trigger for #{@app_one} should exist"
      assert_predicate trigger, :deactivated?
    end

    test "does not insert multiple sequential deactivated records" do
      IntegrationInstallTrigger.deactivate(integration: @app_one, install_type: :file_added)
      IntegrationInstallTrigger.deactivate(integration: @app_one, install_type: :file_added)

      assert_equal 1, IntegrationInstallTrigger.where(integration: @app_one, deactivated: true).count
    end

    test "can be deactivated after being reactivated" do
      IntegrationInstallTrigger.deactivate(integration: @app_one, install_type: :file_added)
      create(:integration_install_trigger, integration: @app_one, install_type: :file_added)
      IntegrationInstallTrigger.deactivate(integration: @app_one, install_type: :file_added)

      assert_equal 2, IntegrationInstallTrigger.where(integration: @app_one, deactivated: true).count
    end
  end

  context "callbacks" do
    test "should_install? is optional and defaults to true" do
      trigger = create(:integration_install_trigger, install_type: :user_created, integration: @app_one)
      refute trigger.handler.respond_to?(:should_install?)
      assert_predicate trigger, :should_install?
    end

    test "validate_trigger is optional and defaults to true" do
      trigger = create(:integration_install_trigger, install_type: :user_created, integration: @app_one)
      refute trigger.handler.respond_to?(:validate_trigger)
      assert_predicate trigger, :validate_trigger
    end

    test "validate_trigger only runs on create" do
      trigger = create(:integration_install_trigger, install_type: :user_created, integration: @app_one)
      trigger.update(install_type: :file_added, path: "invalid_path")

      refute_predicate trigger.reload, :validate_trigger
    end
  end
end
