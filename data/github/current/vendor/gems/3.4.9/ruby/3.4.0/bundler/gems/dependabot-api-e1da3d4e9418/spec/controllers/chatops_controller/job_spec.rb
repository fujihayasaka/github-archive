# frozen_string_literal: true

require "rails_helper"
require "chatops/controller/rspec"

RSpec.describe ChatopsController, :cloud do
  include ActiveSupport::Testing::TimeHelpers

  include_context "chatops controller"

  describe "job" do
    let(:update_job) do
      FactoryBot.create(:update_job, :processing,
                        trigger_type: :install)
    end

    # stagger states for more interesting output
    before do
      frozen_time = Time.find_zone("UTC").parse("2019-11-11 10:05")
      update_job.update!(created_at: frozen_time)
      update_job.history.find { |t| t.to_state == "enqueued" }.
        update!(created_at: frozen_time + 55.minutes + 29.seconds)
      update_job.history.find { |t| t.to_state == "processing" }.
        update!(created_at: frozen_time + 60.minutes)
    end

    it "returns state" do
      chat "dependabot job #{update_job.id}", "user", "#dependabot-ops"
      expect(chatop_response).to include("Job #{update_job.id} - install")
      expect(chatop_response).
        to include("2019-11-11 10:05:00 UTC - created\n")
      expect(chatop_response).
        to include("2019-11-11 11:00:29 UTC - enqueued (after 55m29.0s)")
      expect(chatop_response).
        to include("2019-11-11 11:05:00 UTC - processing (after 4m31.0s)")
    end

    it "links to related activity in splunk" do
      chat "dependabot job #{update_job.id}", "user", "#dependabot-ops"

      expect(chatop_response).to include("splunk.githubapp.com",
                                         CGI.escape("gh.dependabot_api.update_job.id=#{update_job.id}"))
    end

    it "provides a link to Splunk for the API events" do
      chat "dependabot job #{update_job.id}", "user", "#dependabot-ops"

      expect(chatop_response).
        to include("splunk.githubapp.com",
                   CGI.escape("gh_app=dependabot-api #{update_job.id}"))
    end

    it "provides a link to Splunk for monolith events" do
      chat "dependabot job #{update_job.id}", "user", "#dependabot-ops"

      expect(chatop_response).
        to include("splunk.githubapp.com",
                   CGI.escape("index=rails gh.repo.id=#{update_job.update_config.repo.github_id}"))
    end

    it "explains missing job_id" do
      chat "dependabot job 321", "user", "#dependabot-ops"
      expect(chatop_error).to include("Couldn't find job.")
    end

    context "with job error" do
      let!(:branch_not_found_error) do
        FactoryBot.create(:update_job_error,
                          error_type: :branch_not_found,
                          error_details: {
                            "branch-name": "master",
                          },
                          update_job: update_job)
      end

      before do
        update_job.transition_to!(:processed_with_errors,
                                  errors: [branch_not_found_error])
      end

      it "includes the error body" do
        chat "dependabot job #{update_job.id}", "user", "#dependabot-ops"
        expect(chatop_response).to include("Job #{update_job.id} - install")
        expect(chatop_response).to include("branch `master`")
      end
    end

    context "for a job run on Actions" do
      let(:update_job) do
        create(:update_job, :processed, :on_gh_actions, actions_workflow_run_id: 42)
      end

      it "prints actions_workflow_run_id" do
        chat "dependabot job #{update_job.id}", "use", "#dependabot-ops"
        expect(chatop_response).
          to include("Actions workflow run id: 42")
      end
    end

    context "with job dependencies" do
      let(:update_job) do
        FactoryBot.create(:update_job, :processing,
                          trigger_type: :install,
                          dependencies: ["minimist"])
      end

      it "includes dependency details" do
        chat "dependabot job #{update_job.id}", "user", "#dependabot-ops"
        expect(chatop_response).to include("Dependencies: minimist")
      end
    end

    describe "--dry-run argument" do
      context "with public repo" do
        before do
          update_job.update_config.repo.update!(private: false)
        end

        it "includes the repo url and core dry-run details" do
          chat "dependabot job #{update_job.id} --dry-run", "user", "#dependabot-ops"
          repo = update_job.update_config.repo
          expect(chatop_response).to include("Repository: #{repo.github_url}")
          expect(chatop_response).to include("(public) dry-run this update in dependabot-core:")
          expect(chatop_response).to include(
            "bin/dry-run.rb bundler \"hmarr/business\""
          )
        end
      end

      context "with a private repo" do
        before do
          update_job.update_config.repo.update!(private: true)
        end

        it "includes the repo url and debugger dry-run details" do
          chat "dependabot job #{update_job.id} --dry-run", "user", "#dependabot-ops"
          repo = update_job.update_config.repo
          expect(chatop_response).to include("Repository: #{repo.github_url}")
          expect(chatop_response).to include("(private) dry-run this update using dependabot-update-debugger:")
          expect(chatop_response).to include(
            "bin/dry-run.rb bundler \"hmarr/business\""
          )
        end
      end
    end

    context "querying by github_request_id" do
      it "returns state" do
        request_id = update_job.github_request_id
        chat "dependabot job --github-request-id #{request_id}", "user",
             "#dependabot-ops"
        expect(chatop_response).to include("Job #{update_job.id} - install")
      end

      it "explains missing job" do
        chat "dependabot job --github-request-id 321", "user", "#dependabot-ops"
        expect(chatop_error).to include("Couldn't find job.")
      end
    end

    context "querying by pull request" do
      let(:update_job) do
        FactoryBot.create(:update_job, :processing,
                          trigger_type: :scan,
                          dependencies: ["minimist"])
      end

      let(:pull_request) do
        FactoryBot.create(:pull_request, repo: update_job.repo, update_job: update_job, github_number: 7)
      end

      it "returns state" do
        pr = "#{update_job.repo.account.github_login}/#{update_job.repo.name}##{pull_request.github_number}"
        chat "dependabot job --pr #{pr}", "user", "#dependabot-ops"
        expect(chatop_response).to include("Job #{update_job.id} - scan")
      end

      it "explains missing job" do
        chat "dependabot job --pr a/b#321", "user", "#dependabot-ops"
        expect(chatop_error).to include("Couldn't find job.")
      end
    end

    context "change the job timeout" do
      let(:job) { create(:update_job) }

      it "updates the job timeout" do
        chat "dependabot job #{job.id} --set-timeout #{2.hours.seconds}", "user", "#dependabot-ops"

        expect(response).to have_http_status(:ok)
        expect(chatop_response).to include("Job #{job.id} - #{job.trigger_type}")
        expect(job.reload.max_updater_run_time).to eql(2.hours.seconds.to_i)
      end
    end
  end
end
