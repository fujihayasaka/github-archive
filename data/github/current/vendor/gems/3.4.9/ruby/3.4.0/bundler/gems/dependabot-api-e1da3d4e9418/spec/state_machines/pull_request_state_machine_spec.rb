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
end
