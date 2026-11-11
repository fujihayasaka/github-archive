# frozen_string_literal: true

require "rails_helper"

RSpec.describe Routes::Badges::CompatibilityScore do
  subject(:instance) { described_class.new(context) }

  let(:context) { { request: request } }
  let(:request) do
    instance_double(ActionDispatch::Request, params: params, headers: headers)
  end
  let(:headers) { { "Accept": "text/html" } }
  let(:params) do
    ActiveSupport::HashWithIndifferentAccess.new(
      "dependency-name" => dependency_name,
      "package-manager" => package_manager,
      "new-version" => new_version_param,
      "previous-version" => previous_version_param,
    )
  end
  let(:dependency_name) { "pg" }
  let(:package_manager) { "bundler" }
  let(:new_version_param) { "0.21.0" }
  let(:previous_version_param) { "0.20.0" }
  let(:repo) { FactoryBot.create(:repo, private: false) }
  let(:redis) { Dependabot.redis }

  before { redis.flushdb }

  context "with an invalid package manager" do
    let(:package_manager) { "fedex" }

    it { is_expected.to respond_with_status(400) }
    it { is_expected.to respond_with_body_that_matches(/Invalid package man/) }
  end

  context "when there isn't enough data to show a badge" do
    it { is_expected.to respond_with_status(200) }
    it { is_expected.to respond_with_body_that_matches("</svg>") }

    it "increments the metric for the grey badge" do
      expect(MetricsClient).to receive(:increment).
        with("compatibility_scores.badges_rendered",
             tags: { package_manager: "bundler", colour: "grey" })
      instance.call
    end
  end

  context "when there is enough data to show a badge" do
    before do
      FactoryBot.create_list(
        :pull_request, 5,
        created_at: 1.hour.ago,
        repo: repo,
        base_commit_ci_status: "success",
        dependabot_commit_ci_status: "success",
        dependencies:
          [{ name: "pg", version: "0.21.0", previous_version: "0.20.0" }],
      )
    end

    it { is_expected.to respond_with_status(200) }
    it { is_expected.to respond_with_body_that_matches("</svg>") }
    it { is_expected.to respond_with_body_that_matches("100%") }
    it { is_expected.to respond_with_body_that_matches("#3C1") }
    it { is_expected.to respond_with_body_that_matches("compatibility") }

    it "only accesses up to the latest 250 CI runs" do
      expect(instance.send(:pull_request_counts)).to include(
        "success" => 5,
      )
    end

    it "increments the metric for the green badge" do
      expect(MetricsClient).to receive(:increment).
        with("compatibility_scores.badges_rendered",
             tags: { package_manager: "bundler", colour: "green" })
      instance.call
    end

    context "with a JSON header" do
      let(:headers) { { "Accept": "application/json" } }

      it { is_expected.to respond_with_status(200) }
      it { is_expected.to respond_with_body_that_matches("candidate-updates") }

      context "and cached values" do
        it "returns the cached values" do
          # Cache the current number of passing PRs
          instance.call

          # Update the current number of passing PRs to 0
          PullRequest.update_all(dependabot_commit_ci_status: "failure")

          # Check that the old number of passing PRs is returned
          expect(
            JSON.parse(described_class.new(context).call.last.first).
              fetch("data").fetch("attributes").fetch("successful-updates")
          ).to eq(5)
        end
      end
    end

    context "for a post-1.0.0 dependency" do
      before do
        FactoryBot.create_list(
          :pull_request, 5,
          repo: repo,
          base_commit_ci_status: "success",
          dependabot_commit_ci_status: "success",
          dependencies:
            [{ name: "pg", version: "1.21.0", previous_version: "1.20.0" }],
        )
      end

      it { is_expected.to respond_with_status(200) }
      it { is_expected.to respond_with_body_that_matches("</svg>") }
      it { is_expected.to respond_with_body_that_matches("100%") }
      it { is_expected.to respond_with_body_that_matches("#3C1") }
      it { is_expected.to respond_with_body_that_matches("compatibility") }
    end
  end
end
