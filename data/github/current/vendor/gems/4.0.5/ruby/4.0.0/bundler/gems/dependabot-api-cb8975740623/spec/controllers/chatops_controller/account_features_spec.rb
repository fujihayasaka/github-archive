# frozen_string_literal: true

require "rails_helper"
require "chatops/controller/rspec"

RSpec.describe ChatopsController, :cloud do
  include ActiveSupport::Testing::TimeHelpers

  include_context "chatops controller"

  let(:account) do
    FactoryBot.create(:account, github_login: "rails")
  end

  let(:user) { "user" }
  let(:channel) { "#dependabot-ops" }
  let(:account_name) { account.github_login }

  describe "account features" do
    subject(:run_chatop) do
      chat "dependabot account features #{account_name}",
           user,
           channel
    end

    it "outputs the state of chatops-managed features" do
      run_chatop

      expect(chatop_response).to match(/global_tokens *\| *false/)
    end

    context "with an account that doesn't exist" do
      let(:account_name) { "sinatra" }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "Account `sinatra` not found, do you need to specify a `--tenant`?"
        )
      end
    end

    context "with an enable request" do
      it "returns an error" do
        chat "dependabot account features enable #{account_name} job_sqs_stage",
             user,
             channel

        expect(chatop_error).to include(
          "Did you mean `.dependabot account feature enable #{account_name} job_sqs_stage`?"
        )
      end
    end
  end

  describe "account feature enable" do
    subject(:run_chatop) do
      chat "dependabot account feature enable #{account_name} #{feature}",
           user,
           channel
    end

    let(:feature) { "global_tokens" }

    it "enables the feature flag" do
      expect { run_chatop }.to change { account.feature_enabled?(feature) }.
        from(false).
        to(true)
    end

    context "with an account that doesn't exist" do
      let(:account_name) { "sinatra" }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "Account `sinatra` not found, do you need to specify a `--tenant`?"
        )
      end
    end

    context "with a space in the feature name" do
      let(:feature) { "global tokens" }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "Feature `global tokens` cannot be managed via chatops"
        )
      end
    end

    context "with a hyphon in the feature name" do
      let(:feature) { "global-tokens" }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "Feature `global-tokens` cannot be managed via chatops"
        )
      end
    end

    context "with a disallowed feature" do
      let(:feature) { "super_admin_power" }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "Feature `super_admin_power` cannot be managed via chatops"
        )

        expect(account.feature_enabled?(feature)).to be false
      end
    end
  end

  describe "account feature disable" do
    subject(:run_chatop) do
      chat "dependabot account feature disable #{account_name} #{feature}",
           user,
           channel
    end

    let(:feature) { "global_tokens" }

    before { account.enable_feature(feature) } # rubocop:disable Dependabot/NoLocalFeatureFlags

    it "disables the feature flag" do
      expect { run_chatop }.to change { account.feature_enabled?(feature) }.
        from(true).
        to(false)
    end

    context "with an account that doesn't exist" do
      let(:account_name) { "sinatra" }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "Account `sinatra` not found, do you need to specify a `--tenant`?"
        )

        expect(account.feature_enabled?(feature)).to be true
      end
    end

    context "with a space in the feature name" do
      let(:feature) { "global tokens" }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "Feature `global tokens` cannot be managed via chatops"
        )
      end
    end

    context "with a hyphon in the feature name" do
      let(:feature) { "global-tokens" }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "Feature `global-tokens` cannot be managed via chatops"
        )
      end
    end

    context "with a disallowed feature" do
      let(:feature) { "super_admin_power" }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "Feature `super_admin_power` cannot be managed via chatops"
        )

        expect(account.feature_enabled?(feature)).to be true
      end
    end
  end
end
