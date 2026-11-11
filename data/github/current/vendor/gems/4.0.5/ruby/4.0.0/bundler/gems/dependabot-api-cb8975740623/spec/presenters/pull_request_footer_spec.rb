# frozen_string_literal: true

require "rails_helper"

RSpec.describe PullRequestFooter do
  subject(:presenter) do
    described_class.new(
      update_job: update_job,
      updated_dependencies: updated_dependencies,
      outdated_ignore_conditions_removed: false,
      grouped_update: grouped_update
    )
  end

  let(:grouped_update) { false }
  let(:update_job) { FactoryBot.build_stubbed(:update_job) }
  let(:updated_dependencies) { [updated_dependency] }
  let(:updated_dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: "1.5.0",
      previous_version: previous_version,
      requirements:
        [{ file: "Gemfile", requirement: "~> 1.5.0", groups: [], source: nil }],
      previous_requirements:
        [{ file: "Gemfile", requirement: "~> 0.9.0", groups: [], source: nil }],
      package_manager: "bundler",
    )
  end
  let(:multiple_updated_dependencies) do
    [
      Dependabot::Dependency.new(
        name: "business",
        version: "1.5.0",
        previous_version: previous_version,
        requirements: [
          { file: "Gemfile", requirement: "~> 1.5.0", groups: [], source: nil },
        ],
        previous_requirements: [
          { file: "Gemfile", requirement: "~> 0.9.0", groups: [], source: nil },
        ],
        package_manager: "bundler",
      ),
      Dependabot::Dependency.new(
        name: "statesman",
        version: "2.0.0",
        previous_version: "1.8.0",
        requirements: [
          { file: "Gemfile", requirement: "~> 2.0.0", groups: [], source: nil },
        ],
        previous_requirements: [
          { file: "Gemfile", requirement: "~> 1.8.0", groups: [], source: nil },
        ],
        package_manager: "bundler",
      ),
    ]
  end
  let(:previous_version) { "0.9.0" }

  describe "#footer_text" do
    subject(:footer_text) { presenter.footer_text }

    context "cloud", :cloud do
      it { is_expected.to include("compatibility score") }
    end

    context "enterprise", :enterprise do
      it { is_expected.not_to include("compatibility score") }
    end

    context "proxima", :proxima do
      it { is_expected.not_to include("compatibility score") }
    end

    it { is_expected.not_to include("Warning") }
    it { is_expected.not_to include("automatically merge") }

    context "for an account with rebases disabled" do
      let(:update_job) { FactoryBot.create(:update_job, :processing) }

      before { update_job.update_config.update!(rebase_strategy: "disabled") }

      it { is_expected.not_to include("resolve any conflicts") }
      it { is_expected.to include("trigger a rebase") }
    end

    context "when the previous version was a git SHA", :cloud do
      let(:previous_version) { "cd8274d15fa3ae2ab983129fb037999f264ba9a7" }

      it { is_expected.not_to include("compatibility score") }
    end

    context "for an active update config" do
      let(:update_job) do
        FactoryBot.create(
          :update_job, :processing,
          update_config: update_config,
        )
      end
      let(:update_config) { FactoryBot.create(:update_config, :active) }

      it { is_expected.not_to include("maximum of 5") }
    end

    context "for a multi-dependency PR", :cloud do
      let(:updated_dependencies) { multiple_updated_dependencies }

      it { is_expected.not_to include("compatibility score") }
    end

    context "for a non-security update" do
      it { is_expected.not_to include("disable automated security fix PRs") }
    end

    context "for a security only update" do
      let(:update_job) { FactoryBot.build_stubbed(:update_job, :security) }

      it { is_expected.to include("disable automated security fix PRs") }
    end
  end
end
