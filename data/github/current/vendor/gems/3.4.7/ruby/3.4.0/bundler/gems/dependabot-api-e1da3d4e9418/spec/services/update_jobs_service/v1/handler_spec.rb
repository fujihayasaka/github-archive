# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateJobsService::V1::Handler do
  include GzipHelpers

  let(:service) do
    DependabotApi::V1::UpdateJobsService.new(described_class.new)
  end

  let(:repo) do
    FactoryBot.create(:repo, github_id: 42)
  end

  let(:update_config) do
    FactoryBot.create(:update_config, repo: repo)
  end

  let(:update_job) do
    FactoryBot.create(:update_job,
                      :processed,
                      update_config: update_config)
  end

  let(:params) do
    {
      repository_github_id: repo.github_id,
      update_job_id: update_job.id,
    }
  end

  describe "list_jobs" do
    subject(:response) do
      service.call_rpc :ListJobs, params
    end

    let(:params) do
      {
        repository_github_id: repo.github_id,
        update_config_id: update_config.id,
      }
    end

    it "returns a list of jobs and the update_config" do
      create(:update_job, update_config: update_config)
      expect(response.update_jobs.size).to be(1)
      expect(response.update_config.id).to be(update_config.id)
    end

    it "does not list jobs that were created more than 14 days ago" do
      fifteen_days_ago = Time.current - 15.days
      create(:update_job, update_config: update_config, created_at: fifteen_days_ago)
      expect(response.update_jobs.size).to be(0)
      expect(response.update_config.id).to be(update_config.id)
    end

    it "does not list graph jobs" do
      create(:update_job, command: :graph, update_config: update_config)
      expect(response.update_jobs.size).to be(0)
      expect(response.update_config.id).to be(update_config.id)
    end

    context "given an update config ID that isn't associated with the repo" do
      let(:params) do
        {
          repository_github_id: repo.github_id,
          update_config_id: another_update_config.id,
        }
      end
      let(:another_update_config) do
        FactoryBot.create(:update_config)
      end

      it "returns a not found error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:not_found)
        expect(response.msg).to eql("UpdateConfig ID not found.")
      end
    end

    context "but an update job has invalid data which fails to serialize" do
      before do
        failed_update_job = FactoryBot.create(:update_job, update_config: update_config)
        failed_update_job.update_job_errors.create!(error_type: :branch_not_found,
                                                    error_details: "this should not be string")
      end

      it "does not return an error, excludes the job that failed to serialize" do
        create(:update_job, update_config: update_config)
        expect(response.update_jobs.size).to be(1)
        expect(response.update_config.id).to be(update_config.id)
      end
    end
  end

  describe "get_job_status" do
    subject(:response) do
      service.call_rpc :GetJobStatus, params
    end

    it "serializes the current state of the update job correctly" do
      expect(response.update_job.id).to eql(update_job.id)
      expect(response.update_job.state).to be(:PROCESSED)
      expect(response.update_job.warnings).to be_empty

      finished_at = response.update_job.finished_at.to_i
      expected_finished_at = update_job.last_transition.created_at.to_i

      expect(finished_at).to be_within(1.second).of(expected_finished_at)

      expect(response.update_job.last_error).to be_nil
    end

    context "the job processed with an error and a warning" do
      let(:update_job) do
        FactoryBot.create(:update_job,
                          :scheduled,
                          :processed_with_errors,
                          update_config: update_config)
      end

      let!(:ruby_job_error) do
        FactoryBot.create(:update_job_error,
                          error_type: :branch_not_found,
                          error_details: { "branch-name": "master" },
                          update_job: update_job)
      end

      let!(:ruby_job_warning) do
        FactoryBot.create(:update_job_warning,
                          warn_type: "deprecated_method",
                          warn_title: "Deprecated Method Used",
                          warn_description: "This method will be removed in future versions.",
                          update_job: update_job)
      end

      it "serializes the last error and warning as part of the update job" do
        expect(response.update_job.state).to be(:PROCESSED_WITH_ERRORS)

        last_update_error = response.update_job.last_error
        last_update_warning = response.update_job.warnings.first

        expect(last_update_error.id).to eql(ruby_job_error.id)
        expect(last_update_error.type).to eql("branch_not_found")
        expect(last_update_error.msg).
          to eql("Dependabot couldn't find the branch master")
        expect(last_update_error.details).
          to eql("Dependabot was set up to create pull requests against the branch `master`, but couldn't find it.")

        expect(last_update_warning.id).to eql(ruby_job_warning.id)
        expect(last_update_warning.type).to eql("deprecated_method")
        expect(last_update_warning.title).to eql("Deprecated Method Used")
        expect(last_update_warning.description).to eql("This method will be removed in future versions.")
      end
    end

    context "the repo doesn't exist" do
      before { repo.delete }

      it "returns a not found error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:not_found)
        expect(response.msg).to eql("Repository ID not found.")
      end
    end

    context "the job doesn't exist" do
      before { update_job.delete }

      it "returns a not found error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:not_found)
        expect(response.msg).to eql("Job ID not found.")
      end
    end

    context "the job exists, but belongs to a different repo" do
      let(:update_job) { FactoryBot.create(:update_job) }

      it "returns a not found error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:not_found)
        expect(response.msg).to eql("Job ID not found.")
      end
    end
  end

  describe "get_job_status_by_github_request_id" do
    subject(:response) do
      service.call_rpc :GetJobStatusByGithubRequestId, params
    end

    let(:params) do
      {
        repository_github_id: repo.github_id,
        github_request_id: update_job.github_request_id,
      }
    end

    it "serializes the current state of the update job correctly" do
      expect(response.update_job.id).to eql(update_job.id)
      expect(response.update_job.state).to be(:PROCESSED)

      finished_at = response.update_job.finished_at.to_i
      expected_finished_at = update_job.last_transition.created_at.to_i

      expect(finished_at).to be_within(1.second).of(expected_finished_at)

      expect(response.update_job.last_error).to be_nil
    end

    context "the job processed with an error" do
      let(:update_job) do
        FactoryBot.create(:update_job,
                          :scheduled,
                          :processed_with_errors,
                          update_config: update_config)
      end

      let!(:ruby_job_error) do
        FactoryBot.create(:update_job_error,
                          error_type: :branch_not_found,
                          error_details: {
                            "branch-name": "master",
                          },
                          update_job: update_job)
      end

      it "serializes the last error as part of the update job" do
        expect(response.update_job.state).to be(:PROCESSED_WITH_ERRORS)

        last_update_error = response.update_job.last_error

        expect(last_update_error.id).to eql(ruby_job_error.id)
        expect(last_update_error.type).to eql("branch_not_found")
        expect(last_update_error.msg).
          to eql("Dependabot couldn't find the branch master")
        expect(last_update_error.details).
          to eql("Dependabot was set up to create pull requests against "\
                 "the branch `master`, but couldn't find it.")
      end
    end

    context "the repo doesn't exist" do
      before { repo.delete }

      it "returns a not found error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:not_found)
        expect(response.msg).to eql("Repository ID not found.")
      end
    end

    context "the job doesn't exist" do
      before { update_job.delete }

      it "returns a not found error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:not_found)
        expect(response.msg).to eql("Job not found.")
      end
    end

    context "the job exists, but belongs to a different repo" do
      let(:update_job) do
        FactoryBot.create(:update_job)
      end

      it "returns a not found error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:not_found)
        expect(response.msg).to eql("Job not found.")
      end
    end
  end

  describe "get_job_logs" do
    subject(:response) do
      service.call_rpc :GetJobLogs, params
    end

    let(:s3_logs) do
      ""
    end

    before do
      client = Aws::S3::Client.new(stub_responses: true)
      client.stub_responses(:get_object, body: gzip(s3_logs))
      allow(Aws::S3::Client).to receive(:new).and_return(client)
    end

    context "the repository and job exist" do
      it "serializes the current state of the update job correctly" do
        expect(response.update_job.id).to eql(update_job.id)
        expect(response.update_job.state).to be(:PROCESSED)

        finished_at = response.update_job.finished_at.to_i
        expected_finished_at = update_job.last_transition.created_at.to_i

        expect(finished_at).to be_within(1.second).of(expected_finished_at)

        expect(response.update_job.last_error).to be_nil
      end

      context "the job processed with an error" do
        let(:update_job) do
          FactoryBot.create(:update_job,
                            :scheduled,
                            :processed_with_errors,
                            update_config: update_config)
        end

        let!(:ruby_job_error) do
          FactoryBot.create(:update_job_error,
                            error_type: :branch_not_found,
                            error_details: {
                              "branch-name": "master",
                            },
                            update_job: update_job)
        end

        it "serializes the last error as part of the update job" do
          expect(response.update_job.state).to be(:PROCESSED_WITH_ERRORS)

          last_update_error = response.update_job.last_error

          expect(last_update_error.id).to eql(ruby_job_error.id)
          expect(last_update_error.type).to eql("branch_not_found")
          expect(last_update_error.msg).
            to eql("Dependabot couldn't find the branch master")
          expect(last_update_error.details).
            to eql("Dependabot was set up to create pull requests against "\
                   "the branch `master`, but couldn't find it.")
        end
      end

      context "there are no s3 logs available" do
        it "serializes a blank value for update job logs" do
          expect(response.update_job_logs).to be_blank
        end
      end
    end

    context "the repo doesn't exist" do
      before { repo.delete }

      it "returns a not found error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:not_found)
        expect(response.msg).to eql("Repository ID not found.")
      end
    end

    context "the job doesn't exist" do
      before { update_job.delete }

      it "returns a not found error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:not_found)
        expect(response.msg).to eql("Job ID not found.")
      end
    end

    context "the job exists, but belongs to a different repo" do
      let(:update_job) do
        FactoryBot.create(:update_job)
      end

      it "returns a not found error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:not_found)
        expect(response.msg).to eql("Job ID not found.")
      end
    end
  end

  describe "get_job_logs_by_github_request_id" do
    subject(:response) do
      service.call_rpc :GetJobLogsByGithubRequestId, params
    end

    let(:s3_logs) do
      ""
    end

    let(:params) do
      {
        repository_github_id: repo.github_id,
        github_request_id: update_job.github_request_id,
      }
    end

    before do
      client = Aws::S3::Client.new(stub_responses: true)
      client.stub_responses(:get_object, body: gzip(s3_logs))
      allow(Aws::S3::Client).to receive(:new).and_return(client)
    end

    context "the repository and job exist" do
      it "serializes the current state of the update job correctly" do
        expect(response.update_job.id).to eql(update_job.id)
        expect(response.update_job.state).to be(:PROCESSED)

        finished_at = response.update_job.finished_at.to_i
        expected_finished_at = update_job.last_transition.created_at.to_i

        expect(finished_at).to be_within(1.second).of(expected_finished_at)

        expect(response.update_job.last_error).to be_nil
      end

      context "the job processed with an error" do
        let(:update_job) do
          FactoryBot.create(:update_job,
                            :scheduled,
                            :processed_with_errors,
                            update_config: update_config)
        end

        let!(:ruby_job_error) do
          FactoryBot.create(:update_job_error,
                            error_type: :branch_not_found,
                            error_details: {
                              "branch-name": "master",
                            },
                            update_job: update_job)
        end

        it "serializes the last error as part of the update job" do
          expect(response.update_job.state).to be(:PROCESSED_WITH_ERRORS)

          last_update_error = response.update_job.last_error

          expect(last_update_error.id).to eql(ruby_job_error.id)
          expect(last_update_error.type).to eql("branch_not_found")
          expect(last_update_error.msg).
            to eql("Dependabot couldn't find the branch master")
          expect(last_update_error.details).
            to eql("Dependabot was set up to create pull requests against "\
                   "the branch `master`, but couldn't find it.")
        end
      end

      context "there are no s3 logs available" do
        it "serializes a blank value for update job logs" do
          expect(response.update_job_logs).to be_blank
        end
      end
    end

    context "the repo doesn't exist" do
      before { repo.delete }

      it "returns a not found error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:not_found)
        expect(response.msg).to eql("Repository ID not found.")
      end
    end

    context "the job doesn't exist" do
      before { update_job.delete }

      it "returns a not found error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:not_found)
        expect(response.msg).to eql("Job not found.")
      end
    end

    context "the job exists, but belongs to a different repo" do
      let(:update_job) do
        FactoryBot.create(:update_job)
      end

      it "returns a not found error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:not_found)
        expect(response.msg).to eql("Job not found.")
      end
    end
  end

  describe "get_job_errors" do
    subject(:response) do
      service.call_rpc :GetJobErrors, params
    end

    let(:params) do
      {
        repository_github_id: repo.github_id,
        update_job_ids: [update_job_with_error.id, update_job_without_error.id],
      }
    end

    let(:update_job_with_error) do
      FactoryBot.create(:update_job,
                        :processed_with_errors,
                        update_config: update_config)
    end

    let(:update_job_without_error) do
      FactoryBot.create(:update_job,
                        :processed,
                        update_config: update_config)
    end

    let!(:job_error) do
      FactoryBot.create(:update_job_error,
                        error_type: :branch_not_found,
                        error_details: { "branch-name": "main" },
                        update_job: update_job_with_error)
    end

    it "returns only jobs with errors" do
      expect(response.update_jobs_with_errors.size).to eq(1)
      expect(response.update_jobs_with_errors.first.id).to eq(update_job_with_error.id)
    end

    it "serializes the job, configuration, and errors correctly according to the protobuf definition" do
      expect(response.update_jobs_with_errors.size).to eq(1)

      job_response = response.update_jobs_with_errors.first

      expect(job_response.id).to eq(update_job_with_error.id)
      expect(job_response.state).to eq(:PROCESSED_WITH_ERRORS)
      expect(job_response.update_config_id).to eq(update_config.id)
      expect(job_response.runner_type).to eq(update_job_with_error.runner_type)
      expect(job_response.package_ecosystem.name).to eq(:BUNDLER)

      expect(job_response.errors).not_to be_empty
      expect(job_response.errors.size).to eq(1)

      error_response = job_response.errors.first
      expect(error_response.id).to eq(job_error.id)
      expect(error_response.type).to eq("branch_not_found")
      expect(error_response.msg).to eq("Dependabot couldn't find the branch main")
      expect(error_response.details).to include("Dependabot was set up to create pull requests")
    end

    context "when multiple jobs have errors" do
      let(:another_job_with_error) do
        FactoryBot.create(:update_job,
                          :processed_with_errors,
                          update_config: update_config)
      end

      let(:params) do
        {
          repository_github_id: repo.github_id,
          update_job_ids: [update_job_with_error.id, another_job_with_error.id, update_job_without_error.id],
        }
      end

      before do
        FactoryBot.create(:update_job_error,
                          error_type: :unknown_error,
                          error_details: {},
                          update_job: another_job_with_error)
      end

      it "returns all jobs with errors" do
        expect(response.update_jobs_with_errors.size).to eq(2)
        job_ids = response.update_jobs_with_errors.map(&:id)
        expect(job_ids).to contain_exactly(update_job_with_error.id, another_job_with_error.id)
      end
    end

    context "when no jobs have errors" do
      let(:params) do
        {
          repository_github_id: repo.github_id,
          update_job_ids: [update_job_without_error.id],
        }
      end

      it "returns an empty list" do
        expect(response.update_jobs_with_errors).to be_empty
      end
    end

    context "when update_job_ids is empty" do
      let(:params) do
        {
          repository_github_id: repo.github_id,
          update_job_ids: [],
        }
      end

      it "returns an invalid argument error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:invalid_argument)
        expect(response.msg).to eql("update_job_ids cannot be empty")
      end
    end

    context "the repo doesn't exist" do
      before { repo.delete }

      it "returns a not found error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:not_found)
        expect(response.msg).to eql("Repository ID not found.")
      end
    end

    context "when job ids belong to a different repo" do
      let(:other_repo) { FactoryBot.create(:repo) }
      let(:other_update_config) { FactoryBot.create(:update_config, repo: other_repo) }
      let(:other_job) do
        FactoryBot.create(:update_job,
                          :processed_with_errors,
                          update_config: other_update_config)
      end

      let(:params) do
        {
          repository_github_id: repo.github_id,
          update_job_ids: [other_job.id],
        }
      end

      it "returns an empty list" do
        expect(response.update_jobs_with_errors).to be_empty
      end
    end
  end
end
