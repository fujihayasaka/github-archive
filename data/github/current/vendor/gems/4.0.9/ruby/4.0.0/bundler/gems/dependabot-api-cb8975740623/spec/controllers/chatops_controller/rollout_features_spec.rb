# frozen_string_literal: true

require "rails_helper"
require "chatops/controller/rspec"

RSpec.describe ChatopsController, :cloud do
  include_context "chatops controller"

  let(:user) { "user" }
  let(:channel) { "#dependabot-ops" }

  let(:current_rollout_features) { %w(test_feature_a test_feature_b) }

  before do
    Dependabot.flipper["test_feature_a"].enable_percentage_of_actors(10) # rubocop:disable Dependabot/NoLocalFeatureFlags
    stub_const("ChatopRolloutFeatures::PERMITTED_ROLLOUT_FEATURES", current_rollout_features)
  end

  describe "rollout features" do
    subject(:run_chatop) do
      chat "dependabot rollout features",
           user,
           channel
    end

    it "outputs the state of chatops-managed features" do
      run_chatop

      expect(chatop_response).to match(/test_feature_a *\| *10%/)
      expect(chatop_response).to match(/test_feature_b *\| *0%/)
    end

    context "when there are no features being rolled out" do
      let(:current_rollout_features) { [] }

      it "returns an error" do
        run_chatop

        expect(chatop_response).to include(
          "No features currently being rolled out."
        )
      end
    end

    describe "rollout feature actors" do
      subject(:run_chatop) do
        chat "dependabot rollout feature actors #{feature} #{percentage}",
             user,
             channel
      end

      let(:feature) { "test_feature_a" }
      let(:percentage) { "25" }

      def current_actors_percent
        Dependabot.flipper["test_feature_a"].percentage_of_actors_value # rubocop:disable Dependabot/NoLocalFeatureFlags
      end

      it "updates the actors percentage for the given feature" do
        expect { run_chatop }.to change { current_actors_percent }.from(10).to(25)

        expect(chatop_response).to match(/test_feature_a is now enabled for 25% of actors/)
      end

      context "when given a feature that is not permitted for rollout" do
        let(:feature) { "test_feature_c" }

        it "returns an expressive error message" do
          run_chatop

          expect(chatop_error).to include(
            "Feature `test_feature_c` cannot be managed via chatops"
          )
        end
      end

      context "when given a humanized percentage" do
        let(:percentage) { "25%" }

        it "updates the actors percentage for the given feature" do
          expect { run_chatop }.to change { current_actors_percent }.from(10).to(25)

          expect(chatop_response).to match(/test_feature_a is now enabled for 25% of actors/)
        end
      end

      context "when given a non-numerical percentage" do
        let(:percentage) { "twenty five" }

        it "returns an expressive error message" do
          expect { run_chatop }.not_to change { current_actors_percent }.from(10)

          expect(chatop_error).to include(
            "Please provide the target percentage as an integer value"
          )
        end
      end

      context "when given a real number percentage" do
        let(:percentage) { "24.9" }

        it "returns an expressive error message" do
          expect { run_chatop }.not_to change { current_actors_percent }.from(10)

          expect(chatop_error).to include(
            "Please provide the target percentage as an integer value"
          )
        end
      end
    end
  end
end
