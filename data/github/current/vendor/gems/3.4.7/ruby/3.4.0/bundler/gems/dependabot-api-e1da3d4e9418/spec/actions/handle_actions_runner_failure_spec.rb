# frozen_string_literal: true

require "rails_helper"

RSpec.describe HandleActionsRunnerFailure do
  include ActiveJob::TestHelper

  subject(:handler) { described_class.new(update_job: update_job, error: error) }

  let(:repo) { update_job.update_config.repo }

  let(:octokit_error) do
    Octokit::Error.from_response(error_response)
  end

  let(:github_graphql_endpoint) { Dependabot::Application.target_github_graphql_endpoint }

  let(:dependency_update_body) do
    fixture("github_responses/mark_github_job_errored/success.json")
  end

  before do
    github_token = "top secret"
    allow(GitHubHelpers).
      to receive(:installation_access_token_for).
      and_return(github_token)

    stub_request(:post, github_graphql_endpoint).
      to_return(
        status: 200,
        body: dependency_update_body,
        headers: { "Content-Type" => "application/json" },
      )
  end

  context "when there no error given for a Version update" do
    let(:update_job) { FactoryBot.create(:update_job, :version_update, :processing) }
    let(:error) { nil }

    it "sets the job to processed_with_errors" do
      expect { handler.run }.
        to change { update_job.current_state(force_reload: true) }.from("processing").to("processed_with_errors")

      expect(update_job.update_job_errors.count).to be(1)

      job_error = update_job.update_job_errors.last
      expect(job_error.error_type).to eql("actions_service_unknown")
      expect(job_error.error_details).to be_empty
    end

    it "does not attempt to notify GitHub the job has failed" do
      perform_enqueued_jobs do
        handler.run
      end

      expect(WebMock).not_to have_requested(:post, github_graphql_endpoint)
    end
  end

  context "when there no error given for a Security update" do
    let(:update_job) { FactoryBot.create(:update_job, :security_update, :processing) }
    let(:error) { nil }

    it "sets the job to processed_with_errors" do
      expect { handler.run }.
        to change { update_job.current_state(force_reload: true) }.from("processing").to("processed_with_errors")

      expect(update_job.update_job_errors.count).to be(1)

      job_error = update_job.update_job_errors.last
      expect(job_error.error_type).to eql("actions_service_unknown")
      expect(job_error.error_details).to be_empty
    end

    it "attempts to notify GitHub the job has failed" do
      perform_enqueued_jobs do
        handler.run
      end

      expect(WebMock).to have_requested(:post, github_graphql_endpoint).
        with { |req| req.body =~ /"databaseId":#{update_job.github_request_id}/ }
    end
  end

  shared_examples "an actions service error" do
    context "with a Version Update" do
      let(:update_job) { FactoryBot.create(:update_job, :version_update, :processing) }

      it "sets the job to processed_with_errors" do
        expect { handler.run }.
          to change { update_job.current_state(force_reload: true) }.from("processing").to("processed_with_errors")

        expect(update_job.update_job_errors.count).to be(1)

        job_error = update_job.update_job_errors.last
        expect(job_error.error_type).to eql(expected_error_type)
        expect(job_error.error_details).to eql({ "message" => expected_error_message })
      end

      it "does not attempt to notify GitHub the job has failed" do
        perform_enqueued_jobs do
          handler.run
        end

        expect(WebMock).not_to have_requested(:post, github_graphql_endpoint)
      end
    end

    context "with an enqueued Version Update" do
      let(:update_job) { FactoryBot.create(:update_job, :version_update, :enqueued) }

      it "sets the job to processed_with_errors" do
        expect { handler.run }.
          to change { update_job.current_state(force_reload: true) }.from("enqueued").to("processed_with_errors")

        expect(update_job.update_job_errors.count).to be(1)

        job_error = update_job.update_job_errors.last
        expect(job_error.error_type).to eql(expected_error_type)
        expect(job_error.error_details).to eql({ "message" => expected_error_message })
      end

      it "does not attempt to notify GitHub the job has failed" do
        perform_enqueued_jobs do
          handler.run
        end

        expect(WebMock).not_to have_requested(:post, github_graphql_endpoint)
      end
    end

    context "with a Security Update" do
      let(:update_job) { FactoryBot.create(:update_job, :security_update, :processing) }

      it "sets the job to processed_with_errors" do
        expect { handler.run }.
          to change { update_job.current_state(force_reload: true) }.from("processing").to("processed_with_errors")

        expect(update_job.update_job_errors.count).to be(1)

        job_error = update_job.update_job_errors.last
        expect(job_error.error_type).to eql(expected_error_type)
        expect(job_error.error_details).to eql({ "message" => expected_error_message })
      end

      it "attempts to notify GitHub the job has failed" do
        perform_enqueued_jobs do
          handler.run
        end

        expect(WebMock).to have_requested(:post, github_graphql_endpoint).
          with { |req| req.body =~ /"databaseId":#{update_job.github_request_id}/ }
      end
    end
  end

  context "with an Octokit::InternalServerError" do
    let(:error_response) do
      {
        status: 500,
        body: "Failed to run dynamic workflow.",
      }
    end
    let(:error) { octokit_error }

    let(:expected_error_type) { "actions_service_failed" }
    let(:expected_error_message) { "Failed to run dynamic workflow." }

    it_behaves_like "an actions service error"
  end

  context "with an Octokit::NotFound error" do
    let(:error_response) do
      {
        status: 404,
        body: nil,
      }
    end

    let(:error) { octokit_error }

    let(:expected_error_type) { "actions_service_repository_not_found" }
    let(:expected_error_message) { nil }

    it_behaves_like "an actions service error"
  end

  context "with an Octokit::ServiceUnavailable error" do
    let(:error_response) do
      {
        status: 503,
        body: "Run dynamic workflow service unavailable.",
      }
    end

    let(:error) { octokit_error }

    let(:expected_error_type) { "actions_service_unavailable" }
    let(:expected_error_message) { "Run dynamic workflow service unavailable." }

    it_behaves_like "an actions service error"
  end

  context "with an Octokit::TooManyRequests error" do
    let(:error_response) do
      {
        status: 403,
        body: "rate limit exceeded",
      }
    end

    let(:error) { octokit_error }

    let(:expected_error_type) { "octokit_rate_limited" }
    let(:expected_error_message) { "rate limit exceeded" }

    it_behaves_like "an actions service error"
  end

  context "with an Octokit::Unauthorized error" do
    let(:error_response) do
      {
        status: 401,
        response_headers: {},
        body: "Bad credentials",
      }
    end

    let(:error) { octokit_error }

    let(:expected_error_type) { "octokit_unauthorized" }
    let(:expected_error_message) { "Bad credentials" }

    it_behaves_like "an actions service error"
  end

  context "with an Octokit::UnprocessableEntity error" do
    let(:error_response) do
      {
        status: 422,
        body: "No ref found for: #{repo.default_branch}.",
      }
    end

    let(:error) { octokit_error }

    let(:expected_error_type) { "actions_service_unprocessable" }
    let(:expected_error_message) { "No ref found for: #{repo.default_branch}." }

    it_behaves_like "an actions service error"
  end

  context "with a generic runtime error" do
    let(:error) { RuntimeError.new("oh no!") }

    let(:expected_error_type) { "actions_service_unknown" }
    let(:expected_error_message) { "oh no!" }

    it_behaves_like "an actions service error"
  end
end
