# frozen_string_literal: true

require "rails_helper"
require "chatops/controller/rspec"

RSpec.describe ChatopsController, :cloud do
  include ActiveSupport::Testing::TimeHelpers

  include_context "chatops controller"

  describe "info" do
    let!(:account) do
      FactoryBot.create(
        :account,
        github_login: "rails"
      )
    end

    let(:security_updates_enabled) { nil }
    let!(:repository) do
      FactoryBot.create(
        :repo,
        :active,
        account: account,
        name: "rails",
        security_updates_enabled: security_updates_enabled,
      )
    end

    let!(:repository_first_access) do
      repo = FactoryBot.create(
        :repo,
        :active,
        account: account,
        name: "webpacker",
      )

      FactoryBot.create(
        :repository_access,
        account_id: account.id,
        github_id: repo.github_id
      )
    end

    let!(:repository_second_access) do
      repo = FactoryBot.create(
        :repo,
        :active,
        account: account,
        name: "spring",
      )

      FactoryBot.create(
        :repository_access,
        account_id: account.id,
        github_id: repo.github_id
      )
    end

    # this doesn't have a corresponding entry in the repos table
    let!(:repository_third_access) do
      FactoryBot.create(
        :repository_access,
        account_id: account.id,
        github_id: 1000,
      )
    end

    let!(:rails_ruby_config) do
      repository.update_configs.first
    end

    let!(:rails_js_config) do
      FactoryBot.create(:update_config,
                        :active,
                        :weekly,
                        id: 1234567890,
                        repo: repository,
                        open_pull_requests_limit: 10,
                        package_manager: "npm_and_yarn")
    end

    let!(:paused_repo) do
      FactoryBot.create(:repo, :currently_paused, account: account, name: "paused")
    end

    let!(:inactive_repo) do
      FactoryBot.create(:repo, :will_pause_later, account: account, name: "inactive")
    end

    let!(:old_repo) do
      FactoryBot.create(:repo, account: account, name: "old")
    end

    let(:dependabot_repository_settings_client) do
      instance_double(
        GitHub::Twirp::DependabotRepositorySettings,
        get_repository_settings: OpenStruct.new(dependabot_self_hosted_enabled: false),
      )
    end

    before do
      allow(Dependabot::Application).
        to receive(:dependabot_repository_settings_client).
        and_return(dependabot_repository_settings_client)
    end

    context "when given just an account name" do
      it "explains when an account doesn't exist" do
        chat "dependabot info django", "user", "#dependabot-ops"

        expect(chatop_error).to include(
          "Account `django` not found, do you need to specify a `--tenant`?"
        )
      end

      it "summarizes an account" do
        chat "dependabot info rails", "user", "#dependabot-ops"

        expect(chatop_response).to include(
          "Account: rails - GitHub ID: #{account.github_id}"
        )

        expect(chatop_response).
          to match("rails/rails \| #{repository.github_id}")
        expect(chatop_response).
          to match("rails/old \| #{old_repo.github_id}")

        expect(chatop_response).to include("Selected Repositories (3):")
        expect(chatop_response).to match(
          "not available \| #{repository_third_access.github_id}",
        )
        expect(chatop_response).to match(
          "rails/spring \| #{repository_second_access.github_id}",
        )
        expect(chatop_response).to match(
          "rails/webpacker \| #{repository_first_access.github_id}",
        )
      end

      it "includes a link to the account's activity in splunk" do
        chat "dependabot info rails", "user", "#dependabot-ops"

        expect(chatop_response).to include("splunk.githubapp.com", CGI.escape("gh.owner.id=#{account.github_id}"))
      end
    end

    context "when given a name with owner" do
      it "explains when an account doesn't exist" do
        chat "dependabot info django/django", "user", "#dependabot-ops"

        expect(chatop_error).to include(
          "Account `django` not found, do you need to specify a `--tenant`?"
        )
      end

      it "explains when a repository doesn't exist" do
        chat "dependabot info rails/django", "user", "#dependabot-ops"

        expect(chatop_error).to include(
          "Repository `rails/django` not found."
        )
      end

      it "summarizes an active repository" do
        chat "dependabot info rails/rails", "user", "#dependabot-ops"

        expect(chatop_response).to include(
          "Account: rails - GitHub ID: #{account.github_id}"
        )

        expect(chatop_response).to include(
          "Repository: rails/rails - GitHub ID: #{repository.github_id}"
        )

        expect(chatop_response).to include(
          "Runner Type: #{UpdateJob::RUNNER_ACTIONS}"
        )

        expect(chatop_response).to include("Active")

        expect(chatop_response).to include("Configs:")
        expect(chatop_response).to include(rails_ruby_config.id.to_s)
        expect(chatop_response).to include(rails_js_config.id.to_s)

        expect(chatop_response).to include(
          "No update jobs found!"
        )
      end

      it "reports when a repository uses GitHub-hosted Actions runners with repo config) " do
        allow(dependabot_repository_settings_client).to receive(:get_repository_settings).
          and_return(OpenStruct.new(dependabot_self_hosted_enabled: false))

        chat "dependabot info rails/rails", "user", "#dependabot-ops"

        expect(chatop_response).to include(
          "Runner Type: #{UpdateJob::RUNNER_ACTIONS} - (GitHub-Hosted)"
        )
      end

      it "reports when a repository uses self-hosted Actions runners with repo config" do
        allow(dependabot_repository_settings_client).to receive(:get_repository_settings).
          and_return(OpenStruct.new(dependabot_self_hosted_enabled: true))

        chat "dependabot info rails/rails", "user", "#dependabot-ops"

        expect(chatop_response).to include(
          "Runner Type: #{UpdateJob::RUNNER_ACTIONS} - (Self-Hosted)"
        )
      end

      it "includes a link to the repository's activity in splunk" do
        chat "dependabot info rails/rails", "user", "#dependabot-ops"

        expect(chatop_response).to include("splunk.githubapp.com",
                                           CGI.escape("gh.repo.id=#{repository.github_id}"))
      end

      it "summarizes a paused repository" do
        chat "dependabot info rails/paused", "user", "#dependabot-ops"

        expect(chatop_response).to include(
          "Repository: rails/paused - GitHub ID: #{paused_repo.github_id}"
        )

        expect(chatop_response).to include(
          "Paused at #{paused_repo.paused_at}"
        )
      end

      it "summarizes an inactive repository" do
        chat "dependabot info rails/inactive", "user", "#dependabot-ops"

        expect(chatop_response).to include(
          "Repository: rails/inactive - GitHub ID: #{inactive_repo.github_id}"
        )

        expect(chatop_response).to include(
          "Will pause after #{inactive_repo.will_pause_at}"
        )
      end

      it "summarizes a deactivated repository" do
        chat "dependabot info rails/old", "user", "#dependabot-ops"

        expect(chatop_response).to include(
          "Repository: rails/old - GitHub ID: #{old_repo.github_id}"
        )

        expect(chatop_response).to include("Deactivated")

        expect(chatop_response).to include(
          "No update configs found!"
        )
      end

      it "does not summarize all repos for the account" do
        chat "dependabot info rails/old", "user", "#dependabot-ops"

        expect(chatop_response).not_to include("Selected Repositories (3):")
      end

      it "summaries registries" do
        FactoryBot.create(:registry, :bundler, source: repository, name: "github-acme")

        chat "dependabot info rails/rails", "user", "#dependabot-ops"

        expect(chatop_response).to include("Registries:")
        expect(chatop_response).to match(/\|\s+name\s+\|\s+type\s+\|/)
        expect(chatop_response).to match(/\|\s+github-acme\s+\|\s+rubygems_server\s+\|/)
      end

      it "summaries registries when none are defined" do
        expect(repository.registries).to be_empty

        chat "dependabot info rails/rails", "user", "#dependabot-ops"

        expect(chatop_response).to include("Registries: None")
      end

      it "summarizes an update config's registries when an allowlist is used" do
        _registry = FactoryBot.create(:registry, :bundler, source: repository)
        rails_ruby_config.
          update_config_registries.
          create!(registry_name: "github-acme")

        chat "dependabot info rails/rails", "user", "#dependabot-ops"

        expect(chatop_response).to include("github-acme")
      end

      it "summarizes an update config's registries when all registries are used" do
        _registry = FactoryBot.create(:registry, :bundler, source: repository)
        rails_ruby_config.update!(all_registries: true)

        chat "dependabot info rails/rails", "user", "#dependabot-ops"

        expect(chatop_response).to match(/\|\s+bundler\s+\|.*\|\s+\*\s+\|/)
      end

      context "for a repository with job history" do
        let!(:ruby_jobs) do
          FactoryBot.create_list(:update_job, 5,
                                 update_config: rails_ruby_config,
                                 trigger_type: :push)
        end

        let!(:js_job) do
          FactoryBot.create(:update_job,
                            :timed_out,
                            id: 987654321,
                            update_config: rails_js_config,
                            trigger_type: :manual)
        end

        let(:dependency_group) do
          FactoryBot.create(:dependency_group, name: "ruby-group")
        end

        let(:pull_request) do
          FactoryBot.create(:pull_request,
                            update_config: rails_ruby_config,
                            grouped_update: true,
                            dependency_group: dependency_group)
        end

        let!(:group_ruby_job) do
          pull_request.transition_to!(:updating)
          pull_request.create_rebase_update_jobs.first
        end

        it "summarizes an active repository" do
          chat "dependabot info rails/rails", "user", "#dependabot-ops"

          expect(chatop_response).to include(
            "Account: rails - GitHub ID: #{account.github_id}"
          )

          expect(chatop_response).to include(
            "Repository: rails/rails - GitHub ID: #{repository.github_id}"
          )

          expect(chatop_response).to include(
            "Runner Type: #{UpdateJob::RUNNER_ACTIONS}"
          )

          expect(chatop_response).to include("Active")

          expect(chatop_response).to include("Configs:")
          expect(chatop_response).to include(rails_ruby_config.id.to_s)
          expect(chatop_response).to include(rails_js_config.id.to_s)
          expect(chatop_response).to match(/\|\s+registry_names\s+\|/)
          expect(chatop_response).to match(/\|\s+cron_expression\s+\|/)
          expect(chatop_response).to match(/\|\s+next_enqueue_at\s+\|/)

          expect(chatop_response).to include(
            "Update Config ID #{rails_ruby_config.id} - bundler, directory: /, " \
            "directories: , target_branch: (default branch)"
          )
          ruby_jobs.each do |job|
            expect(chatop_response).to match(/
              #{job.id}\s+\|\s+
              push\s+\|\s+
              pending
              .+\n                       # match the rest of the line
              .+#{job.github_request_id} # expect the github id the next line
            /x)
          end
          # Make sure we have the grouped rebase for this config as well
          expect(chatop_response).to match(/
            #{group_ruby_job.id}\s+\|\s+
            rebase\s+\|\s+
            pending
            .+\n                     # match the rest of the first line
            \|\s+\|\s+ruby-group.+\n # expect group and pr number on new lines
            \|\s+\|\s+PR ##{pull_request.github_number}
          /x)

          expect(chatop_response).to include(
            "Update Config ID #{rails_js_config.id} - npm_and_yarn, directory: /, " \
            "directories: , target_branch: (default branch)"
          )
          expect(chatop_response).to match(/
            #{js_job.id}\s+\|\s+
            manual\s+\|\s+
            timed_out
            .+\n                          # match the rest of the first line
            .+#{js_job.github_request_id} # expect the github id the next line
          /x)
        end

        it "filters configs/jobs by package manager" do
          chat "dependabot info rails/rails --package_manager bundler",
               "user", "#dependabot-ops"

          # Configs are included, filtered:
          expect(chatop_response).to include("Configs:")
          expect(chatop_response).to include(rails_ruby_config.id.to_s)
          expect(chatop_response).not_to include("npm_and_yarn")

          # Jobs are included, filtered:
          expect(chatop_response).to include("Jobs:")
          ruby_jobs.each do |job|
            expect(chatop_response).to include(job.id.to_s)
          end
          expect(chatop_response).not_to include(js_job.id.to_s)
        end

        it "filters jobs by config" do
          chat "dependabot info rails/rails --config #{rails_ruby_config.id}",
               "user", "#dependabot-ops"

          # Config list is skipped:
          expect(chatop_response).to include("Configs:")
          expect(chatop_response).to include(rails_ruby_config.id.to_s)
          expect(chatop_response).not_to include(rails_js_config.id.to_s)

          # Jobs are included, filtered:
          expect(chatop_response).to include("Jobs:")
          ruby_jobs.each do |job|
            expect(chatop_response).to include(job.id.to_s)
          end
          expect(chatop_response).not_to include(js_job.id.to_s)
        end
      end

      context "when a repository uses GitHub-hosted Actions runners" do
        let!(:jobs) do
          Array.new(5) do |i|
            actions_workflow_run_id = 1_000 + i
            create(:update_job, :processed, :on_gh_actions,
                   update_config: rails_ruby_config,
                   trigger_type: :push,
                   actions_workflow_run_id: actions_workflow_run_id)
          end
        end

        before do
          allow(dependabot_repository_settings_client).to receive(:get_repository_settings).
            and_return(OpenStruct.new(dependabot_self_hosted_enabled: false))
        end

        it "includes actions_workflow_run_id in job summaries" do
          column_separator = "\\s+\\|\\s+"
          job_summary_header_pattern = /
            id
            #{column_separator}
            trigger_type
            #{column_separator}
            state
            #{column_separator}
            actions_workflow_run_id
          /x
          job_summary_row_patterns = jobs.each_with_index.map do |job, i|
            actions_workflow_run_id = 1_000 + i
            /
              #{job.id}
              #{column_separator}
              push
              #{column_separator}
              processed
              #{column_separator}
              #{actions_workflow_run_id}
            /x
          end

          chat "dependabot info rails/rails", "user", "#dependabot-ops"

          expect(chatop_response).to match(job_summary_header_pattern)

          job_summary_row_patterns.each do |pattern|
            expect(chatop_response).to match(pattern)
          end
        end
      end

      it "indicates that repository security updates enablement has not been synced yet" do
        chat "dependabot info rails/rails", "user", "#dependabot-ops"

        expect(chatop_response).to include("Security Updates Enablement Unknown")
      end

      context "when repository security updates are enabled" do
        let(:security_updates_enabled) { true }

        specify do
          chat "dependabot info rails/rails", "user", "#dependabot-ops"

          expect(chatop_response).to include("Security Updates Enabled")
        end
      end

      context "when repository security updates are disabled" do
        let(:security_updates_enabled) { false }

        specify do
          chat "dependabot info rails/rails", "user", "#dependabot-ops"

          expect(chatop_response).to include("Security Updates Disabled")
        end
      end
    end

    context "when given a number" do
      it "explains when a repository doesn't exist" do
        chat "dependabot info 987654321", "user", "#dependabot-ops"

        expect(chatop_error).to include(
          "Repository: 987654321 - not found."
        )
      end

      it "summarizes an active repository" do
        chat "dependabot info #{repository.github_id}", "user", "#dependabot-ops"

        expect(chatop_response).to include(
          "Account: rails - GitHub ID: #{account.github_id}"
        )

        expect(chatop_response).to include(
          "Repository: rails/rails - GitHub ID: #{repository.github_id}"
        )

        expect(chatop_response).to include(
          "Runner Type: #{UpdateJob::RUNNER_ACTIONS}"
        )

        expect(chatop_response).to include("Active")

        expect(chatop_response).to include("Configs:")
        expect(chatop_response).to include(rails_ruby_config.id.to_s)
        expect(chatop_response).to include(rails_js_config.id.to_s)

        expect(chatop_response).to include(
          "No update jobs found!"
        )
      end
    end
  end
end
