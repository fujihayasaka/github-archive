# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateJobError, type: :model do
  subject(:update_job_error) do
    FactoryBot.build(:update_job_error, update_job: update_job)
  end

  let(:update_job) do
    FactoryBot.create(:update_job, :processed_with_errors)
  end
  let(:runner_type) { "actions" }

  describe "validations" do
    it { is_expected.to be_valid }

    context "without error_type" do
      before { update_job_error.error_type = nil }

      it { is_expected.not_to be_valid }
    end

    context "without an update_job" do
      before { update_job_error.update_job = nil }

      it { is_expected.not_to be_valid }
    end
  end

  describe "metrics" do
    context "with no associations set" do
      it "emits a metric for an unknown package manager" do
        tags = {
          error_type: "dependency_file_not_evaluatable",
          error_category: "user_error",
          runner_type: runner_type,
        }
        expect(MetricsClient).to receive(:count).with("job.error.created", 1,
                                                      tags: hash_including(tags))

        update_job_error.save!
      end
    end

    context "with git_dependencies_not_reachable" do
      before { update_job_error.error_type = "git_dependencies_not_reachable" }

      context "without repository accesses" do
        it "tags metric with repository_access" do
          tags = {
            error_type: "git_dependencies_not_reachable",
            error_category: "expected_error",
            runner_type: runner_type,
            repository_access: false,
          }
          expect(MetricsClient).to receive(:count).with("job.error.created", 1,
                                                        tags: hash_including(tags))

          update_job_error.save!
        end
      end

      context "with repository accesses" do
        it "tags metric with repository_access" do
          RepositoryAccess.create!(account: update_job.update_config.account, github_id: 1)

          tags = {
            error_type: "git_dependencies_not_reachable",
            error_category: "expected_error",
            runner_type: runner_type,
            repository_access: true,
          }
          expect(MetricsClient).to receive(:count).with("job.error.created", 1,
                                                        tags: hash_including(tags))

          update_job_error.save!
        end
      end
    end
  end

  describe "#error_hash" do
    subject(:error_hash) { update_job_error.error_hash }

    it "returns a hash compatible with UpdateJobErrorPresenter" do
      expect(error_hash).to eq(
        "error-type" => "dependency_file_not_evaluatable",
        "error-detail" => { "message" => "My message" },
      )
    end
  end

  describe "#error_presenter" do
    subject(:error_presenter) { update_job_error.error_presenter }

    it "returns a hash compatible with UpdateJobErrorPresenter" do
      expect(error_presenter).to be_an_instance_of(UpdateJobErrorPresenter)
      expect(error_presenter.issue_type).
        to eq("dependency_file_not_evaluatable")
      expect(error_presenter.issue_detail).
        to eq("My message")
    end
  end

  describe ".ALLOWED_UPDATE_JOB_ERROR_TYPES" do
    specify do
      expect(described_class::ALLOWED_UPDATE_JOB_ERROR_TYPES).to include("job_repo_not_found")
    end
  end
end
