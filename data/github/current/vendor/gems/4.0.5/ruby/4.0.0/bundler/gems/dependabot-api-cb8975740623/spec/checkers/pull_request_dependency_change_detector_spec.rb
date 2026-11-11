# frozen_string_literal: true

require "rails_helper"

RSpec.describe PullRequestDependencyChangeDetector do
  subject(:detector) do
    described_class.new(
      pull_request: pull_request,
      github_details: github_details,
      github_client: github_client,
    )
  end

  let(:pull_request) do
    instance_double(
      PullRequest,
      repo: repo,
      update_config: update_config,
      updated_dependencies: updated_dependencies,
      age_in_days: 3,
    )
  end
  let(:repo) { instance_double(Repo, github_id: 12345) }
  let(:update_config) { instance_double(UpdateConfig, package_manager: "bundler") }
  let(:updated_dependencies) { [instance_double(Dependabot::Dependency, name: "rails")] }

  let(:base) { Struct.new(:sha, :ref).new("basesha", "main") }
  let(:github_details) { Struct.new(:base).new(base) }

  # GitHubHelpers::ClientWithRetries delegates via method_missing, so it can't
  # be verified with instance_double. Octokit::Client is the underlying class
  # the wrapper forwards `#compare` to, so use it for verification here.
  let(:github_client) { instance_double(Octokit::Client) }
  let(:compare_result) { Struct.new(:files).new(compared_files) }
  let(:file_struct) { Struct.new(:filename, :patch) }

  before do
    allow(github_client).to receive(:compare).with(12345, "basesha", "main").and_return(compare_result)
  end

  describe "#changed?" do
    context "when no files have changed" do
      let(:compared_files) { [] }

      it "returns false" do
        expect(detector.changed?).to be(false)
      end
    end

    context "when changed files don't match the package manager regex" do
      let(:compared_files) { [file_struct.new("README.md", "+ rails")] }

      it "returns false" do
        expect(detector.changed?).to be(false)
      end
    end

    context "when matching files don't contain any updated dependency name" do
      let(:compared_files) { [file_struct.new("Gemfile", "+ gem 'sinatra'")] }

      it "returns false" do
        expect(detector.changed?).to be(false)
      end
    end

    context "when a matching file's patch contains an updated dependency name" do
      let(:compared_files) { [file_struct.new("Gemfile.lock", "+ rails (7.1.0)")] }

      it "returns true" do
        expect(MetricsClient).to receive(:gauge).with(
          "pull_request_dependency_change_detector.pr_age_in_days",
          3,
          tags: { errored: false, changed: true },
        )

        expect(detector.changed?).to be(true)
      end

      context "when the dependency name is mixed-case" do
        let(:updated_dependencies) { [instance_double(Dependabot::Dependency, name: "Rails")] }

        it "still matches case-insensitively" do
          expect(detector.changed?).to be(true)
        end
      end
    end

    context "when the compare API returns an UnprocessableEntity error" do
      let(:compared_files) { [] } # unused; compare is re-stubbed below
      let(:pull_request) do
        instance_double(
          PullRequest,
          repo: repo,
          update_config: update_config,
          updated_dependencies: updated_dependencies,
          telemetry_attributes: { "gh.dependabot_api.pr.id" => 7 },
          age_in_days: 42,
        )
      end

      before do
        allow(github_client).to receive(:compare).and_raise(error)
      end

      context "when the message indicates the diff took too long" do
        let(:error) { Octokit::UnprocessableEntity.new(body: "this diff is taking too long to generate") }

        it "swallows the error, logs, and emits an errored gauge" do
          expect(Dependabot::Logger).to receive(:error).with(
            hash_including(
              msg: "diff took too long",
              "code.namespace": "pull_request_dependency_change_detector",
              "exception.message": include("this diff is taking too long"),
              "gh.dependabot_api.pr.id" => 7,
            ),
          )
          expect(MetricsClient).to receive(:gauge).with(
            "pull_request_dependency_change_detector.pr_age_in_days",
            42,
            tags: { errored: true, changed: nil },
          )

          expect { detector.changed? }.not_to raise_error
        end
      end

      context "when the error has a different message" do
        let(:error) { Octokit::UnprocessableEntity.new(body: "something else went wrong") }

        it "re-raises the error" do
          expect(Dependabot::Logger).not_to receive(:error)
          expect(MetricsClient).not_to receive(:gauge)

          expect { detector.changed? }.to raise_error(Octokit::UnprocessableEntity)
        end
      end
    end
  end
end
