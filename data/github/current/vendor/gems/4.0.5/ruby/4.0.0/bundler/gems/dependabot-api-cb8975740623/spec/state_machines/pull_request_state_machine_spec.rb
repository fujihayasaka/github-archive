# frozen_string_literal: true

require "rails_helper"

RSpec.describe PullRequestStateMachine do
  include ActiveJob::TestHelper

  describe "callbacks" do
    context "after merge" do
      it "reports the compatibility score of the PR" do
        pull_request = create(:pull_request)

        pull_request.transition_to(:merged)

        expect(CaptureCompatibilityScoreJob).to have_been_enqueued
      end
    end
  end

  describe "denormalizing current state" do
    let(:pull_request) { create(:pull_request, :up_to_date) }

    it "sets the current_state column on transition" do
      expect(pull_request.current_state).to eq("up_to_date")

      pull_request.transition_to!(:closed)
      pull_request.reload
      expect(pull_request.attributes["current_state"]).to eq("closed")

      pull_request.transition_to!(:up_to_date)
      pull_request.reload
      expect(pull_request.attributes["current_state"]).to eq("up_to_date")
    end

    it "resetting the state machine reloads the denormalized column" do
      pull_request.current_state = "closed"
      pull_request.state_machine.reset
      expect(pull_request.current_state).to eq("up_to_date")
    end
  end
end
