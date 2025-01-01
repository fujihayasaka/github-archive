# typed: true
# frozen_string_literal: true

require "test_helper"

class AutomaticAppInstallationTest < GitHub::TestCase
  class AutomaticAppInstallationTestHandler < AutomaticAppInstallation::Handlers::BaseHandler
  end

  context ".trigger" do
    test "should instrument a valid trigger" do
      events = []
      GlobalInstrumenter.subscribe("integration_install") do |name, _, _, _, payload|
        events << { name: name, payload: payload }
      end

      integration = create(:integration, name: "Don't worry, be Appy")
      create(:integration_install_trigger, integration: integration, install_type: :button_clicked)
      actor = create(:user)

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      AutomaticAppInstallation.trigger(type: :file_added, originator: integration, actor: actor)

      expected_payload = {
        trigger_type: :file_added,
        originator: integration,
        actor: actor,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event[:payload]
      assert_equal 1, GitHub.dogstats.increments("automatic_app_installation.triggered", tags: ["trigger:file_added", "async:true"]).size
    end

    test "should attempt installation if processed synchronously" do
      integration = create(:integration, name: "Don't worry, be Appy")
      create(:integration_install_trigger, integration: integration, install_type: :button_clicked)

      handlers = {
        button_clicked: AutomaticAppInstallationTestHandler,
      }

      handler = stub
      handler.expects(:validate).once.returns(AutomaticAppInstallation::Handlers::BaseHandler::Result.success)
      handler.expects(:install_integration).once

      originator = stub
      actor = stub

      AutomaticAppInstallationTestHandler.expects(:new).with do |args|
        assert install_trigger = args[:install_triggers].first
        assert_equal "button_clicked", install_trigger.install_type
        assert_equal originator, args[:originator]
        assert_equal actor, args[:actor]
      end.returns(handler)


      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      AutomaticAppInstallation.stub_const(:TRIGGER_HANDLERS, handlers) do
        result = AutomaticAppInstallation.trigger(type: :button_clicked, originator: originator, actor: actor, async: false)
        assert result.first.success?
      end
      assert_equal 1, GitHub.dogstats.increments("automatic_app_installation.triggered", tags: ["trigger:button_clicked", "async:false"]).size
    end
  end

  context ".attempt_installation" do
    test "uses the correct event handler to install integrations" do
      integration = create(:integration, name: "Don't worry, be Appy")
      create(:integration_install_trigger, integration: integration, install_type: :file_added)

      handlers = {
        file_added: AutomaticAppInstallationTestHandler,
      }

      handler = stub
      handler.expects(:validate).once.returns(AutomaticAppInstallation::Handlers::BaseHandler::Result.success)
      handler.expects(:install_integration).once

      originator = stub
      actor = stub

      AutomaticAppInstallationTestHandler.expects(:new).with do |args|
        assert install_trigger = args[:install_triggers].first
        assert_equal "file_added", install_trigger.install_type
        assert_equal originator, args[:originator]
        assert_equal actor, args[:actor]
      end.returns(handler)

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      AutomaticAppInstallation.stub_const(:TRIGGER_HANDLERS, handlers) do
        AutomaticAppInstallation.attempt_installation(trigger: :file_added, originator: originator, actor: actor)
      end
      assert_equal 1, GitHub.dogstats.increments("automatic_app_installation.attempt_installation", tags: ["trigger:file_added"]).size
    end

    test "instruments a failure when the handler does not validate" do
      integration = create(:integration, name: "Don't worry, be Appy")
      create(:integration_install_trigger, integration: integration, install_type: :file_added)

      handlers = {
        file_added: AutomaticAppInstallationTestHandler,
      }

      handler = stub
      handler.expects(:validate).once.returns(
        AutomaticAppInstallation::Handlers::BaseHandler::Result.failure(reason: :actor_not_supplied),
      )
      handler.expects(:install_integration).never

      originator = stub

      AutomaticAppInstallationTestHandler.expects(:new).with do |args|
        assert install_trigger = args[:install_triggers].first
        assert_equal "file_added", install_trigger.install_type
        assert_equal originator, args[:originator]
        assert_nil args[:actor]
      end.returns(handler)

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      AutomaticAppInstallation.stub_const(:TRIGGER_HANDLERS, handlers) do
        result = AutomaticAppInstallation.attempt_installation(trigger: :file_added, originator: originator, actor: nil)
        refute result.first.success?
      end

      expected_options = [
        "automatic_app_installation.handler_validation_failed",
        tags: ["trigger:file_added", "reason:actor_not_supplied"],
      ]
      assert_equal 1, GitHub.dogstats.increments(*expected_options).size
    end
  end
end
