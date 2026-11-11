# frozen_string_literal: true

require "rails_helper"
require "chatops/controller/rspec"

RSpec.describe ChatopsController, :cloud do
  include ActiveSupport::Testing::TimeHelpers

  include_context "chatops controller"

  describe "hydro_status" do
    before do
      Flipper.enable(VulnerabilityAlertProcessor.topic_pause_flag)
    end

    it "shows the status of the processors" do
      chat "dependabot hydro-status", "user", "#dependabot-ops"

      expect(chatop_response).
        to match(/repository_dependency_update *\| *paused/)
      expect(chatop_response).
        to match(/repository_push *\| *processing/)
    end
  end

  describe "hydro_pause" do
    let(:pause_flag) do
      :hydro_pause_repository_dependency_update
    end

    before do
      refute Flipper.enabled?(pause_flag)
    end

    it "pauses hydro consumer" do
      chat "dependabot hydro-pause repository_dependency_update",
           "user", "#dependabot-ops"
      expect(chatop_response).to include("Paused work on app")
      assert Flipper.enabled?(pause_flag)
    end

    context "when already paused" do
      before do
        Flipper.enable(pause_flag)
      end

      it "explains the previous state" do
        chat "dependabot hydro-pause repository_dependency_update",
             "user", "#dependabot-ops"
        expect(chatop_response).to include("Already paused work on app")
        assert Flipper.enabled?(pause_flag)
      end
    end

    context "with the all topics argument" do
      it "pauses all consumers" do
        chat "dependabot hydro-pause all", "user", "#dependabot-ops"
        expect(chatop_response).to include("Paused work on app")
        ProcessorManager::PROCESSORS.each_value do |processor|
          assert Flipper.enabled?(processor.topic_pause_flag)
        end
      end
    end

    it "handles unrecognized handlers" do
      chat "dependabot hydro-pause reticulating_splines",
           "user", "#dependabot-ops"
      expect(chatop_error).to include("Didn't recognise the hydro processor")
      refute Flipper.enabled?(pause_flag)
    end
  end

  describe "hydro_resume" do
    let(:pause_flag) do
      :hydro_pause_repository_dependency_update
    end

    before do
      Flipper.enable(pause_flag)
    end

    it "resumes hydro consumer" do
      chat "dependabot hydro-resume repository_dependency_update",
           "user", "#dependabot-ops"
      expect(chatop_response).to include("Resumed work on app")
      refute Flipper.enabled?(pause_flag)
    end

    context "when already resumed" do
      before do
        Flipper.disable(pause_flag)
      end

      it "explains the previous state" do
        chat "dependabot hydro-resume repository_dependency_update",
             "user", "#dependabot-ops"
        expect(chatop_response).to include("Already resumed work on app")
        refute Flipper.enabled?(pause_flag)
      end
    end

    context "with the all topics argument" do
      before do
        chat "dependabot hydro-pause all", "user", "#dependabot-ops"
      end

      it "resumes all consumers" do
        chat "dependabot hydro-resume all", "user", "#dependabot-ops"
        expect(chatop_response).to include("Resumed work on app")
        ProcessorManager::PROCESSORS.each_value do |processor|
          refute Flipper.enabled?(processor.topic_pause_flag)
        end
      end
    end

    it "handles unrecognized handlers" do
      chat "dependabot hydro-resume reticulating_splines",
           "user", "#dependabot-ops"
      expect(chatop_error).to include("Didn't recognise the hydro processor")
      assert Flipper.enabled?(pause_flag)
    end
  end
end
