# frozen_string_literal: true

require "rails_helper"

RSpec.describe PendingPullRequestStateMachine do
  include ActiveSupport::Testing::TimeHelpers

  describe "denormalizing current state" do
    let(:pending_pull_request) { create(:pending_pull_request) }

    it "sets the current_state column on transition" do
      expect(pending_pull_request.current_state).to eq("pending")

      pending_pull_request.transition_to!(:created)
      pending_pull_request.reload
      expect(pending_pull_request.attributes["current_state"]).to eq("created")
    end

    it "resetting the state machine reloads the denormalized column" do
      pending_pull_request.current_state = "created"
      pending_pull_request.state_machine.reset
      expect(pending_pull_request.current_state).to eq("pending")
    end
  end
end
