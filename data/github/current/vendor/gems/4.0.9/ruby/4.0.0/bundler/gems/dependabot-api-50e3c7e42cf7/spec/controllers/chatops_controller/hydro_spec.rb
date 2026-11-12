# frozen_string_literal: true

require "rails_helper"
require "chatops/controller/rspec"

RSpec.describe ChatopsController, :cloud do
  include ActiveSupport::Testing::TimeHelpers

  include_context "chatops controller"

  describe "hydro_status" do
    before do
      ProcessorManager.pause(VulnerabilityAlertProcessor.slug)
    end

    after do
      ProcessorManager.resume(VulnerabilityAlertProcessor.slug)
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
      refute ProcessorManager.paused?("repository_dependency_update")
    end

    after do
      ProcessorManager.resume("repository_dependency_update")
    end

    it "pauses hydro consumer" do
      chat "dependabot hydro-pause repository_dependency_update",
           "user", "#dependabot-ops"
      expect(chatop_response).to include("Paused work on app")
      assert ProcessorManager.paused?("repository_dependency_update")
    end

    context "when already paused" do
      before do
        ProcessorManager.pause("repository_dependency_update")
      end

      after do
        ProcessorManager.resume("repository_dependency_update")
      end

      it "explains the previous state" do
        chat "dependabot hydro-pause repository_dependency_update",
             "user", "#dependabot-ops"
        expect(chatop_response).to include("Already paused work on app")
        assert ProcessorManager.paused?("repository_dependency_update")
      end
    end

    context "with the all topics argument" do
      after do
        ProcessorManager.resume("all")
      end

      it "pauses all consumers" do
        chat "dependabot hydro-pause all", "user", "#dependabot-ops"
        expect(chatop_response).to include("Paused work on app")
        ProcessorManager::PROCESSORS.each_value do |processor|
          assert ProcessorManager.paused?(processor.slug)
        end
      end
    end

    it "handles unrecognized handlers" do
      chat "dependabot hydro-pause reticulating_splines",
           "user", "#dependabot-ops"
      expect(chatop_error).to include("Didn't recognise the hydro processor")
    end
  end

  describe "hydro_resume" do
    let(:pause_flag) do
      :hydro_pause_repository_dependency_update
    end

    before do
      ProcessorManager.pause(VulnerabilityAlertProcessor.slug)
    end

    it "resumes hydro consumer" do
      chat "dependabot hydro-resume repository_dependency_update",
           "user", "#dependabot-ops"
      expect(chatop_response).to include("Resumed work on app")
      refute ProcessorManager.paused?(VulnerabilityAlertProcessor.slug)
    end

    context "when already resumed" do
      before do
        ProcessorManager.resume(VulnerabilityAlertProcessor.slug)
      end

      it "explains the previous state" do
        chat "dependabot hydro-resume repository_dependency_update",
             "user", "#dependabot-ops"
        expect(chatop_response).to include("Already resumed work on app")
        refute ProcessorManager.paused?(VulnerabilityAlertProcessor.slug)
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
          refute ProcessorManager.paused?(processor.slug)
        end
      end
    end

    it "handles unrecognized handlers" do
      chat "dependabot hydro-resume reticulating_splines",
           "user", "#dependabot-ops"
      expect(chatop_error).to include("Didn't recognise the hydro processor")
    end
  end
end
