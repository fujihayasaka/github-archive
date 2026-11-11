# frozen_string_literal: true

require "rails_helper"

RSpec.describe CaptureCompatibilityScoreJob, type: :job do
  describe "#perform" do
    it "no-ops on GHES", :enterprise do
      pull_request = build(:pull_request)

      expect(CompatibilityScore).not_to receive(:new)

      described_class.new.perform(pull_request)
    end

    it "no-ops on Proxima", :proxima do
      pull_request = build(:pull_request)

      expect(CompatibilityScore).not_to receive(:new)

      described_class.new.perform(pull_request)
    end

    it "no-ops for grouped PRs" do
      pull_request = create_pull_request
      pull_request.updated_dependencies << create(:updated_dependency)

      expect(CompatibilityScore).not_to receive(:new)
    end

    it "delegates to CompatibilityScore", :cloud do
      score = instance_double(CompatibilityScore, pull_request_counts: {})
      allow(CompatibilityScore).to receive(:new).and_return(score)
      pull_request = create_pull_request
      dependency = pull_request.updated_dependencies.first

      expect(CompatibilityScore).
        to receive(:new).
        with(
          dependency_name: dependency.name,
          package_manager: dependency.package_manager,
          new_version: dependency.version,
          previous_version: dependency.previous_version
        )
      expect(score).to receive(:pull_request_counts)

      described_class.new.perform(pull_request)
    end

    it "publishes compatibility information to the metrics client", :cloud do
      pull_request = create_pull_request
      failure_count = 5
      success_count = 95

      stub_compatibility_score(
        pull_request: pull_request,
        failure_count: failure_count,
        success_count: success_count
      )

      expect(MetricsClient).
        to receive(:gauge).
        with(
          "capture_compatibility_score.merged_pr.compatibility_score",
          success_count.to_f / (success_count.to_f + failure_count.to_f)
        )

      described_class.new.perform(pull_request)
    end

    it "logs important details", :cloud do
      pull_request = create_pull_request
      failure_count = 5
      success_count = 95

      stub_compatibility_score(
        pull_request: pull_request,
        failure_count: failure_count,
        success_count: success_count
      )

      expect(Dependabot::Logger).
        to receive(:info)

      described_class.new.perform(pull_request)
    end
  end

  def create_pull_request
    dependency = {
      name: "business",
      version: "1.8.0",
      previous_version: "1.3.0",
      requirements: [],
      previous_requirements: [],
      package_manager: "bundler",
    }
    create(:pull_request, dependencies: [dependency])
  end

  def stub_compatibility_score(pull_request:, success_count:, failure_count:)
    score = stubbed_compatibility_score(success_count: success_count, failure_count: failure_count)
    dependency = pull_request.updated_dependencies.first
    allow(CompatibilityScore).
      to receive(:new).
      with({
             dependency_name: dependency.name,
             package_manager: dependency.package_manager,
             new_version: dependency.version,
             previous_version: dependency.previous_version,
           }).
      and_return(score)
  end

  def stubbed_compatibility_score(success_count:, failure_count:)
    instance_double(
      CompatibilityScore,
      pull_request_counts: {
        "#{GitHub::CheckRun::Conclusion::SUCCESS}": success_count,
        "#{GitHub::CheckRun::Conclusion::FAILURE}": failure_count,
      }
    )
  end
end
