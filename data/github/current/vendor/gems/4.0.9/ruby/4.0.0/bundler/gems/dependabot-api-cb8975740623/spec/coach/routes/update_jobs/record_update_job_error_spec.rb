# frozen_string_literal: true

require "rails_helper"

RSpec.describe Routes::UpdateJobs::RecordUpdateJobError do
  subject(:instance) { described_class.new(context) }

  let(:context) { { request: request, update_job: update_job } }
  let(:request) { instance_double(ActionDispatch::Request, params: params) }
  let(:params) do
    ActiveSupport::HashWithIndifferentAccess.new(
      data: { "error-type" => error_type, "error-details" => error_detail },
    )
  end
  let(:error_type) { "dependency_file_not_evaluatable" }
  let(:error_detail) { { "message" => "My message" } }

  context "for a processing update job" do
    let(:update_job) { FactoryBot.create(:update_job, :processing) }

    it { is_expected.to respond_with_status(204) }

    it "creates an update job error" do
      expect { instance.call }.to change(UpdateJobError, :count).by(1)

      update_job_error = UpdateJobError.last
      expect(update_job_error.error_type).to eq(error_type)
      expect(update_job_error.error_details).to eq(error_detail)
    end

    it "adds the error_type to the error tracker context" do
      allow(Dependabot::Exceptions).to receive(:push)
      instance.call
      expect(Dependabot::Exceptions).to have_received(:push).
        with({ "gh.dependabot_api.update_job_error.error_type": error_type })
    end

    context "with a very long message" do
      let(:error_detail) { { "message" => "a" * 65536 } }

      it "creates an update job error" do
        expect { instance.call }.to change(UpdateJobError, :count).by(1)

        update_job_error = UpdateJobError.last
        expect(update_job_error.error_type).to eq(error_type)
        expect(update_job_error.error_details.fetch("message")).
          to end_with("a...")
      end
    end

    context "with a very long non-string message" do
      let(:error_detail) { { "message" => ("1" * 65536).to_i } }

      it "creates an update job error" do
        expect { instance.call }.to change(UpdateJobError, :count).by(1)

        update_job_error = UpdateJobError.last
        expect(update_job_error.error_type).to eq(error_type)
        expect(update_job_error.error_details.fetch("message")).
          to end_with("1...")
      end
    end

    context "when the update job error already exists" do
      before do
        FactoryBot.create(
          :update_job_error,
          update_job: update_job,
          error_details: error_detail,
        )
      end

      it "does not create another update job error" do
        expect { instance.call }.not_to change(UpdateJobError, :count)
      end
    end

    context "with a runner_error that is a secret_not_found error" do
      let(:error_type) { "runner_error" }
      let(:error_detail) do
        {
          "message" => "fetching credentials: received code 422: "\
                       "{\"errors\":[{\"status\":422,\"title\":\"Secret Not Found\",\"detail\":\"MY_MISSING_PAT\"}]}",
        }
      end

      it "creates a secret_not_found error" do
        expect { instance.call }.to change(UpdateJobError, :count).by(1)

        update_job_error = UpdateJobError.last
        expect(update_job_error.error_type).to eq("secret_not_found")
        expect(update_job_error.error_details).to eq({ "secret-name" => "MY_MISSING_PAT" })
      end
    end

    context "with a actions_workflow_updater error that is a secret_not_found error" do
      let(:error_type) { "actions_workflow_updater" }
      let(:error_detail) do
        {
          "action-error" => "fetching credentials: received code 422: "\
                       "{\"errors\":[{\"status\":422,\"title\":\"Secret Not Found\",\"detail\":\"MY_MISSING_PAT\"}]}",
        }
      end

      it "creates a secret_not_found error" do
        expect { instance.call }.to change(UpdateJobError, :count).by(1)

        update_job_error = UpdateJobError.last
        expect(update_job_error.error_type).to eq("secret_not_found")
        expect(update_job_error.error_details).to eq({ "secret-name" => "MY_MISSING_PAT" })
      end
    end

    context "with a runner_error that is a malformed secret_not_found error" do
      let(:error_type) { "runner_error" }
      let(:error_detail) do
        {
          "message" => "fetching credentials: received code 422: "\
                       "{\"errors\":[{\"status\":422,\"title\":\"Secret Not Found\"}]}",
        }
      end

      before do
        allow(::Failbot).to receive(:report)
      end

      it "creates a runner_error error and reports to failbot" do
        expect { instance.call }.to change(UpdateJobError, :count).by(1)

        expect(::Failbot).to have_received(:report).with(
          RuntimeError.new("Couldn't extract secret name from SecretNotFound error"), {}
        )

        update_job_error = UpdateJobError.last
        expect(update_job_error.error_type).to eq(error_type)
        expect(update_job_error.error_details).to eq(error_detail)
      end
    end

    context "with a regular runner_error error" do
      let(:error_type) { "runner_error" }
      let(:error_detail) do
        {
          "message" => "fetching job: received code 422: "\
                       "{\"errors\":[{\"status\":422,\"title\":\"Unprocessable Entity\","\
                       "\"detail\":\"POST https://api.github.com/app/installations/1234/access_tokens: "\
                       "422 - No repositories were provided.\"}]}",
        }
      end

      it "creates a runner_error error" do
        expect { instance.call }.to change(UpdateJobError, :count).by(1)

        update_job_error = UpdateJobError.last
        expect(update_job_error.error_type).to eq(error_type)
        expect(update_job_error.error_details).to eq(error_detail)
      end
    end

    context "with an octokit_unauthorized error caused by a user supplied token" do
      let(:error_type) { "octokit_unauthorized" }
      let(:error_detail) { nil }
      let(:hostname) { Dependabot::Application.target_github_hostname(update_job.update_config.repo.account) }

      before do
        update_config = update_job.update_config
        update_config.update!(all_registries: true)
        FactoryBot.create(:registry, :git, source: update_job.update_config.repo, name: "my-github", credentials: {
          url: "https://#{hostname}",
          username: "monalisa",
          password: "${{secrets.GIT_PASSWORD}}",
        }.to_json)
      end

      it "creates a private_source_authentication_failure error" do
        expect { instance.call }.to change(UpdateJobError, :count).by(1)

        update_job_error = UpdateJobError.last
        expect(update_job_error.error_type).to eq("private_source_authentication_failure")
        expect(update_job_error.error_details).to eq({ "source" => hostname })
      end

      it "increments the error_map metric" do
        expect { instance.call }.to change(UpdateJobError, :count).by(1)

        expect(MetricsClient).to have_received(:count).
          with("update_job.mapped_error", 1,
               tags: hash_including({
                                      from: "octokit_unauthorized",
                                      to: "private_source_authentication_failure",
                                    }))
      end
    end

    context "with an octokit_unauthorized error caused by the default token" do
      let(:error_type) { "octokit_unauthorized" }
      let(:error_detail) { nil }

      it "creates the octokit_unauthorized error" do
        expect { instance.call }.to change(UpdateJobError, :count).by(1)

        update_job_error = UpdateJobError.last
        expect(update_job_error.error_type).to eq("octokit_unauthorized")
        expect(update_job_error.error_details).to be_nil
      end

      it "doesn't increment the error_map metric" do
        expect { instance.call }.to change(UpdateJobError, :count).by(1)

        expect(MetricsClient).not_to have_received(:count).
          with("update_job.mapped_error", tags: anything)
      end
    end

    context "with an octokit_unauthorized error and an unrelated user token" do
      let(:error_type) { "octokit_unauthorized" }
      let(:error_detail) { nil }

      before do
        update_config = update_job.update_config
        update_config.update!(all_registries: true)
        FactoryBot.create(:registry, :git, source: update_job.update_config.repo, name: "my-gitlab", credentials: {
          url: "https://gitlab.com",
          username: "monalisa",
          password: "${{secrets.GIT_PASSWORD}}",
        }.to_json)
      end

      it "creates the octokit_unauthorized error" do
        expect { instance.call }.to change(UpdateJobError, :count).by(1)

        update_job_error = UpdateJobError.last
        expect(update_job_error.error_type).to eq("octokit_unauthorized")
        expect(update_job_error.error_details).to be_nil
      end
    end
  end
end
