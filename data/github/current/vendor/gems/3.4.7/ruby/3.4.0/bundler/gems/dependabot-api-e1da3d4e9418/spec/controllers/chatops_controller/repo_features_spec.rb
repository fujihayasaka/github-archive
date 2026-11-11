# frozen_string_literal: true

require "rails_helper"
require "chatops/controller/rspec"

RSpec.describe ChatopsController, :cloud do
  include ActiveSupport::Testing::TimeHelpers

  include_context "chatops controller"

  let(:repo) do
    FactoryBot.create(:repo, :bump_test)
  end

  let(:user) { "user" }
  let(:channel) { "#dependabot-ops" }
  let(:repo_nwo) { repo.full_name }

  describe "repo features" do
    subject(:run_chatop) do
      chat "dependabot repo features #{repo_nwo}",
           user,
           channel
    end

    it "outputs the state of chatops-managed features" do
      run_chatop

      expect(chatop_response).to match(/job_sqs_stage *\| *false *\| *false/)
    end

    it "includes `timeout_per_operation` in the list of features" do
      run_chatop

      expect(chatop_response).to match(/timeout_per_operation\s*\|\s*false\s*\|\s*false/)
    end

    context "with an repo that doesn't exist" do
      let(:repo_nwo) { "dependabot/sinatra" }

      before { FactoryBot.create(:account, github_login: "dependabot") }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "Repository `#{repo_nwo}` not found."
        )
      end
    end

    context "with an enable request" do
      it "returns an error" do
        chat "dependabot repo features enable #{repo_nwo} job_sqs_stage",
             user,
             channel

        expect(chatop_error).to include(
          "Did you mean `.dependabot repo feature enable #{repo_nwo} job_sqs_stage`?"
        )
      end
    end
  end

  describe "repo feature enable" do
    subject(:run_chatop) do
      chat "dependabot repo feature enable #{repo_nwo} #{feature}",
           user,
           channel
    end

    # job_sqs_stage controls runner environment (stage vs prod)
    let(:feature) { "job_sqs_stage" }

    it "enables the feature flag" do
      expect { run_chatop }.to change { repo.feature_enabled?(feature) }.
        from(false).
        to(true)
    end

    context "with an repo that doesn't exist" do
      let(:repo_nwo) { "dependabot/sinatra" }

      before { FactoryBot.create(:account, github_login: "dependabot") }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "Repository `#{repo_nwo}` not found."
        )
      end
    end

    context "with a space in the feature name" do
      let(:feature) { "job sqs stage" }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "Feature `#{feature}` cannot be managed via chatops"
        )
      end
    end

    context "with a hyphon in the feature name" do
      let(:feature) { "job-sqs-stage" }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "Feature `#{feature}` cannot be managed via chatops"
        )
      end
    end

    context "with a disallowed feature" do
      let(:feature) { "super_admin_power" }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "Feature `#{feature}` cannot be managed via chatops"
        )

        expect(repo.feature_enabled?(feature)).to be false
      end
    end
  end

  describe "repo feature disable" do
    subject(:run_chatop) do
      chat "dependabot repo feature disable #{repo_nwo} #{feature}",
           user,
           channel
    end

    # job_sqs_stage controls runner environment (stage vs prod)
    let(:feature) { "job_sqs_stage" }

    before { repo.enable_feature(feature) }

    it "disables the feature flag" do
      expect { run_chatop }.to change { repo.feature_enabled?(feature) }.
        from(true).
        to(false)
    end

    context "with an repo that doesn't exist" do
      let(:repo_nwo) { "dependabot/sinatra" }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "Repository `#{repo_nwo}` not found."
        )

        expect(repo.feature_enabled?(feature)).to be true
      end
    end

    context "with a space in the feature name" do
      let(:feature) { "job sqs stage" }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "Feature `#{feature}` cannot be managed via chatops"
        )
      end
    end

    context "with a hyphon in the feature name" do
      let(:feature) { "job-sqs-stage" }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "Feature `#{feature}` cannot be managed via chatops"
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

        expect(repo.feature_enabled?(feature)).to be true
      end
    end
  end
end
