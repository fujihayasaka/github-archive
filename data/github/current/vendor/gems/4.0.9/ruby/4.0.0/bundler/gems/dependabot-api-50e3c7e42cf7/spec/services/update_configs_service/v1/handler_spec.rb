# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateConfigsService::V1::Handler do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:service) do
    DependabotApi::V1::UpdateConfigsService.new(described_class.new)
  end

  describe "deactivate_update_configs" do
    subject(:response) do
      perform_enqueued_jobs(only: ResetConfigFileJob) do
        service.call_rpc :DeactivateUpdateConfigs, repository_github_id: repository_github_id
      end
    end

    let(:repository_github_id) { 42 }

    it "returns a not found error if the repository id doesn't exist" do
      expect(response).to be_a(Twirp::Error)
      expect(response.code).to be(:not_found)
      expect(response.msg).to eql("Repository ID not found.")
    end

    it "returns an empty message of the Repository exists" do
      FactoryBot.create(:repo, github_id: repository_github_id)

      expect(response).to be_a(DependabotApi::V1::DeactivateUpdateConfigsResponse)
    end

    it "deactivates any update configs belonging to the repository and clears its config file path" do
      repo = FactoryBot.create(:repo, :with_config_file, github_id: repository_github_id)
      config = FactoryBot.create(:update_config, :active, repo: repo)

      expect(repo).to be_using_config_file
      expect(config).to be_in_state(:active)

      expect(response).to be_a(DependabotApi::V1::DeactivateUpdateConfigsResponse)

      expect(repo.reload).not_to be_using_config_file
      expect(config.reload.current_state).to eql("deleted")
    end

    it "marks the repository as active", feature: :inactivity_pausing do
      repo = FactoryBot.create(:repo, github_id: repository_github_id)

      repo.update(will_pause_at: 30.days.from_now.utc)

      expect { response }.
        to change { repo.reload.will_pause_at }.
        from(within(1.second).of(30.days.from_now.utc)).to(nil)
    end
  end

  describe "list_update_configs" do
    subject(:response) do
      service.call_rpc(
        :ListUpdateConfigs,
        repository_github_id: repository_github_id,
        owner_github_id: owner_github_id,
        config_file_exists: config_file_exists,
      )
    end

    let(:repository_github_id) { 42 }
    let(:owner_github_id) { 33 }
    let(:config_file_exists) { false }
    let(:expected_default_confg) do
      {
        "allow" => [
          {
            "dependency-type" => "direct",
          },
        ],
        "assignees" => [],
        "ignore" => [],
        "labels" => ["dependencies"],
        "versioning-strategy" => "auto",
      }
    end

    context "when the repo doesn't exist and there isn't a known config file" do
      it "returns a not found error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:not_found)
        expect(response.msg).to eql("Repository ID not found.")
      end

      it "doesn't schedule a remediation attempt" do
        expect(response).to be_a(Twirp::Error)

        expect(RemediateAccountAndRepoActivationJob).not_to have_been_enqueued
      end
    end

    context "when the repo doesn't exist and there is a known config file" do
      let(:config_file_exists) { true }

      it "returns a not found error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:not_found)
        expect(response.msg).to eql("Repository ID not found.")
      end

      it "schedules a remediation attempt" do
        expect(response).to be_a(Twirp::Error)

        expect(RemediateAccountAndRepoActivationJob).to have_been_enqueued.with(
          github_account_id: owner_github_id,
          event_source: "twirp.update_configs_service.list_update_configs",
          github_repo_id: repository_github_id,
        )
      end
    end

    context "when the repository exists" do
      let!(:repo) do
        FactoryBot.create(:repo,
                          :with_config_file,
                          github_id: repository_github_id)
      end

      it "serializes the config file path" do
        expect(response).to be_a(DependabotApi::V1::ListUpdateConfigsResponse)

        expect(response.config_file.path).to eql(".github/dependabot.yml")
        expect(response.config_file.error).to be_nil
      end

      context "and there is a config file error" do
        let!(:config_file_error) do
          FactoryBot.create(:config_file_error,
                            error_type: :unparseable_config_file,
                            error_details: {
                              message: "File is full of bees!",
                            },
                            repo: repo)
        end

        it "serializes the config file error" do
          expect(response).to be_a(DependabotApi::V1::ListUpdateConfigsResponse)

          expect(response.config_file.path).to eql(".github/dependabot.yml")
          expect(response.config_file.error).to be_present

          error = response.config_file.error

          expect(error.id).to eql(config_file_error.id)
          expect(error.type).to eql("unparseable_config_file")
          expect(error.msg).
            to eql("Dependabot couldn't parse the config file "\
                   "at #{repo.config_file_path}")
          expect(error.details).
            to include("File is full of bees!")
        end
      end

      context "and update configs exist" do
        let!(:ruby_config) do
          FactoryBot.create(:update_config,
                            :active,
                            package_manager: "bundler",
                            target_branch: "master",
                            monitored_files: [
                              "Gemfile",
                              "Gemfile.lock",
                            ],
                            repo: repo)
        end

        let!(:ruby_job1) do
          FactoryBot.create(:update_job,
                            :scheduled,
                            :processed,
                            update_config: ruby_config)
        end

        let!(:ruby_job2) do
          FactoryBot.create(:update_job,
                            :scheduled,
                            :timed_out,
                            update_config: ruby_config)
        end

        let!(:ruby_job3) do
          FactoryBot.create(:update_job,
                            :scheduled,
                            :processed_with_errors,
                            update_config: ruby_config)
        end

        let!(:ruby_job_error1) do
          FactoryBot.create(:update_job_error,
                            error_type: :dependency_file_not_evaluatable,
                            update_job: ruby_job3)
        end

        let!(:ruby_job_error2) do
          FactoryBot.create(:update_job_error,
                            error_type: :branch_not_found,
                            error_details: {
                              "branch-name": "master",
                            },
                            update_job: ruby_job3)
        end

        let!(:js_config) do
          FactoryBot.create(:update_config,
                            :rate_limited,
                            package_manager: "npm_and_yarn",
                            target_branch: "develop",
                            monitored_files: [
                              "package.json",
                              "yarn.lock",
                            ],
                            repo: repo)
        end

        let!(:js_job1) do
          FactoryBot.create(:update_job,
                            :scheduled,
                            :processed,
                            update_config: js_config)
        end

        let!(:python_config) do
          FactoryBot.create(:update_config,
                            :active,
                            package_manager: "pip",
                            target_branch: "production",
                            monitored_files: [
                              "requirements.txt",
                            ],
                            repo: repo)
        end

        let!(:composer_config) do
          FactoryBot.create(:update_config,
                            :pending,
                            package_manager: "composer",
                            repo: repo)
        end

        let!(:maven_config) do
          FactoryBot.create(:update_config,
                            :deleted,
                            package_manager: "maven",
                            repo: repo)
        end

        # Ensure we aren't caching the wrong job id
        before do
          ruby_config.reload
        end

        it "returns all of the rate_limited and active configs" do
          expect(response).to be_a(DependabotApi::V1::ListUpdateConfigsResponse)
          expect(response.update_configs.count).to be(3)

          update_config_ids = response.update_configs.map(&:id)
          expected_config_ids = [ruby_config.id, js_config.id, python_config.id]

          expect(update_config_ids).to match_array(expected_config_ids)
        end

        describe "ruby config" do
          let(:config) do
            response.update_configs.find { |uc| uc.id == ruby_config.id }
          end

          let(:last_full_update_run) do
            config.last_full_update_run
          end

          let(:last_update_error) do
            last_full_update_run.last_error
          end

          it "is correctly serialized" do
            expect(config.package_ecosystem.name).to be(:BUNDLER)
            expect(config.package_ecosystem.support).to be(:BETA)

            expect(config.target_branch).to eql("master")

            expect(config.monitored_manifest_files.map(&:path)).
              to eql(["Gemfile", "Gemfile.lock"])

            expect(last_full_update_run).to be_present

            expect(last_full_update_run.id).to eql(ruby_job3.id)
            expect(last_full_update_run.state).to be(:PROCESSED_WITH_ERRORS)

            finished_at = last_full_update_run.finished_at.to_i
            expected_finished_at = ruby_config.last_transition.created_at.to_i

            expect(finished_at).to be_within(1.second).of(expected_finished_at)

            expect(last_update_error).to be_present

            expect(last_update_error.id).to eql(ruby_job_error2.id)
            expect(last_update_error.type).to eql("branch_not_found")
            expect(last_update_error.msg).
              to eql("Dependabot couldn't find the branch master")
            expect(last_update_error.details).
              to eql("Dependabot was set up to create pull requests against "\
                     "the branch `master`, but couldn't find it.")
          end

          it "includes the configuration set by the user as yaml" do
            config_file_values = YAML.safe_load(
              config.serialized_config_file_yml
            )

            expect(config_file_values).to eql(
              "version" => 2,
              "updates" => [
                {
                  "directory" => "/",
                  "package-ecosystem" => "bundler",
                  "schedule" => {
                    "interval" => "daily",
                  },
                  "target-branch" => "master",
                },
              ],
            )
          end

          it "includes the configuration set via defaults as yaml" do
            default_values = YAML.safe_load(
              config.serialized_config_file_defaults_yml
            )

            expect(default_values).to eql(expected_default_confg)
          end
        end

        describe "js config" do
          let(:config) do
            response.update_configs.find { |uc| uc.id == js_config.id }
          end

          let(:last_full_update_run) do
            config.last_full_update_run
          end

          it "is correctly serialized" do
            expect(config.package_ecosystem.name).to be(:NPM)
            expect(config.package_ecosystem.support).to be(:BETA)

            expect(config.target_branch).to eql("develop")

            expect(config.monitored_manifest_files.map(&:path)).
              to eql(["package.json", "yarn.lock"])

            expect(last_full_update_run).to be_present

            expect(last_full_update_run.id).to eql(js_job1.id)
            expect(last_full_update_run.state).to be(:PROCESSED)

            finished_at = last_full_update_run.finished_at.to_i
            expected_finished_at = js_config.last_transition.created_at.to_i

            expect(finished_at).to be_within(1.second).of(expected_finished_at)

            expect(last_full_update_run.last_error).to be_blank
          end

          it "includes the configuration set by the user as yaml" do
            config_file_values = YAML.safe_load(
              config.serialized_config_file_yml
            )

            expect(config_file_values).to eql(
              "version" => 2,
              "updates" => [
                {
                  "directory" => "/",
                  "package-ecosystem" => "npm",
                  "schedule" => {
                    "interval" => "daily",
                  },
                  "target-branch" => "develop",
                },
              ],
            )
          end

          it "includes the configuration set via defaults as yaml" do
            default_values = YAML.safe_load(
              config.serialized_config_file_defaults_yml
            )

            expect(default_values).to eql(expected_default_confg)
          end
        end

        describe "python config" do
          let(:config) do
            response.update_configs.find { |uc| uc.id == python_config.id }
          end

          it "is correctly serialized" do
            expect(config.package_ecosystem.name).to be(:PIP)
            expect(config.package_ecosystem.support).to be(:BETA)

            expect(config.target_branch).to eql("production")

            expect(config.monitored_manifest_files.map(&:path)).
              to eql(["requirements.txt"])

            expect(config.last_full_update_run).to be_blank
          end

          it "includes the configuration set by the user as yaml" do
            config_file_values = YAML.safe_load(
              config.serialized_config_file_yml,
            )

            expect(config_file_values).to eql(
              "version" => 2,
              "updates" => [
                {
                  "directory" => "/",
                  "package-ecosystem" => "pip",
                  "schedule" => {
                    "interval" => "daily",
                  },
                  "target-branch" => "production",
                },
              ],
            )
          end

          it "includes the configuration set via defaults as yaml" do
            default_values = YAML.safe_load(
              config.serialized_config_file_defaults_yml
            )

            expect(default_values).to eql(expected_default_confg)
          end
        end
      end

      it "returns an empty set if no configs exist" do
        expect(response).to be_a(DependabotApi::V1::ListUpdateConfigsResponse)
        expect(response.update_configs).to be_empty
      end

      it "returns an empty set if no active configs exist" do
        FactoryBot.create(:update_config, :deleted, repo: repo)

        expect(response).to be_a(DependabotApi::V1::ListUpdateConfigsResponse)
        expect(response.update_configs).to be_empty
      end
    end

    context "when the repository exists but has no config file and no known config file exists" do
      let!(:repo) do
        FactoryBot.create(:repo, github_id: repository_github_id)
      end

      let!(:ruby_config) do
        FactoryBot.create(:update_config,
                          :active,
                          package_manager: "bundler",
                          target_branch: "master",
                          monitored_files: [
                            "Gemfile",
                            "Gemfile.lock",
                          ],
                          repo: repo)
      end

      it "returns an empty response" do
        expect(response).to be_a(DependabotApi::V1::ListUpdateConfigsResponse)
        expect(response.update_configs).to be_empty
      end

      it "doesn't enqueue a config resync" do
        expect(response).to be_a(DependabotApi::V1::ListUpdateConfigsResponse)

        expect(ResyncRepoConfigFileJob).not_to have_been_enqueued
      end
    end

    context "when the repository exists but has no config file but a known config files exists" do
      let!(:repo) do
        FactoryBot.create(:repo, github_id: repository_github_id)
      end
      let(:config_file_exists) { true }

      let!(:ruby_config) do
        FactoryBot.create(:update_config,
                          :active,
                          package_manager: "bundler",
                          target_branch: "master",
                          monitored_files: [
                            "Gemfile",
                            "Gemfile.lock",
                          ],
                          repo: repo)
      end

      it "returns an empty response" do
        expect(response).to be_a(DependabotApi::V1::ListUpdateConfigsResponse)
        expect(response.update_configs).to be_empty
      end

      it "enqueues a config resync" do
        expect(response).to be_a(DependabotApi::V1::ListUpdateConfigsResponse)

        expect(ResyncRepoConfigFileJob).to have_been_enqueued.with(
          account: repo.account,
          repo_name: repo.name,
          repo_github_id: repo.github_id,
          event_source: "twirp.update_configs_service.list_update_configs",
        )
      end
    end

    context "when the repository exists with configs that are never updated" do
      let!(:repo) do
        FactoryBot.create(:repo,
                          :with_config_file,
                          github_id: repository_github_id)
      end

      let!(:ruby_config) do
        FactoryBot.create(:update_config,
                          :active,
                          package_manager: "bundler",
                          target_branch: "master",
                          monitored_files: [
                            "Gemfile",
                            "Gemfile.lock",
                          ],
                          repo: repo)
      end

      let!(:js_config) do
        FactoryBot.create(:update_config,
                          :rate_limited,
                          package_manager: "npm_and_yarn",
                          target_branch: "develop",
                          update_schedule: "never",
                          monitored_files: [
                            "package.json",
                            "yarn.lock",
                          ],
                          repo: repo)
      end

      it "excludes the never updated config" do
        expect(response).to be_a(DependabotApi::V1::ListUpdateConfigsResponse)
        expect(response.update_configs.count).to be(1)

        expect(response.update_configs.first.id).to eql(ruby_config.id)
      end
    end

    context "when the repository exists with a security updates only config" do
      let!(:repo) do
        FactoryBot.create(:repo,
                          :with_config_file,
                          github_id: repository_github_id)
      end

      let!(:ruby_config) do
        FactoryBot.create(:update_config,
                          :active,
                          package_manager: "bundler",
                          target_branch: "master",
                          monitored_files: [
                            "Gemfile",
                            "Gemfile.lock",
                          ],
                          open_pull_requests_limit: 0,
                          repo: repo)
      end

      it "excludes the security updates only configs" do
        expect(response).to be_a(DependabotApi::V1::ListUpdateConfigsResponse)
        expect(response.update_configs.count).to be(0)
      end
    end
  end

  describe "repository_status" do
    subject(:response) do
      service.call_rpc(:RepositoryStatus,
                       repository_github_id: repository_github_id)
    end

    let(:repository_github_id) { 42 }
    let!(:repo) { FactoryBot.create(:repo, github_id: repository_github_id) }

    context "when the repository doesn't exist" do
      subject(:response) do
        service.call_rpc(:RepositoryStatus,
                         repository_github_id: 43)
      end

      it "returns an error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:not_found)
        expect(response.msg).to eql("Repository ID not found.")
      end
    end

    context "when the repository doesn't have an update config" do
      it "indicates that a config file is not used and version updates are disabled" do
        expect(response).to be_a(DependabotApi::V1::RepositoryStatusResponse)
        expect(response.repository_github_id).to be(repo.github_id)
        expect(response.using_config_file).to be(false)
        expect(response.version_updates_enabled).to be(false)
        expect(response.paused).to be(false)
      end
    end

    context "when the repository is paused", feature: :inactivity_pausing do
      let(:repo) { FactoryBot.create(:repo, github_id: repository_github_id, paused_at: "2022-11-01 11:00:00.195100") }
      let(:update_config) do
        FactoryBot.create(:update_config, :rate_limited, repo: repo)
      end

      it "indicates the repository is paused" do
        expect(response).to be_a(DependabotApi::V1::RepositoryStatusResponse)
        expect(response.repository_github_id).to be(repo.github_id)
        expect(response.using_config_file).to be(false)
        expect(response.version_updates_enabled).to be(false)
        expect(response.paused).to be(true)
      end
    end

    context "when the repository has a Security Update only update config" do
      let!(:update_config) do
        FactoryBot.create(:update_config, :rate_limited, repo: repo)
      end

      it "indicates that a config file is not used and version updates are disabled" do
        expect(response).to be_a(DependabotApi::V1::RepositoryStatusResponse)
        expect(response.repository_github_id).to be(repo.github_id)
        expect(response.using_config_file).to be(false)
        expect(response.version_updates_enabled).to be(false)
      end
    end

    context "when the repository has an update config managed by a dependabot.yml file" do
      let!(:repo) { FactoryBot.create(:repo, :with_config_file, github_id: repository_github_id) }
      let!(:update_config) do
        FactoryBot.create(:update_config, :rate_limited, repo: repo)
      end

      it "indicates that a config file is used and version updates are enabled" do
        expect(response).to be_a(DependabotApi::V1::RepositoryStatusResponse)
        expect(response.repository_github_id).to be(repo.github_id)
        expect(response.using_config_file).to be(true)
        expect(response.version_updates_enabled).to be(true)
      end
    end

    # This shouldn't happen under normal circumstances, we unset repo.config_file_path when the
    # last configuration managed by it is removed.
    context "when the repository is in a malformed state with an deleted config that is managed by a file" do
      let!(:repo) { FactoryBot.create(:repo, :with_config_file, github_id: repository_github_id) }
      let!(:update_config) do
        FactoryBot.create(:update_config, :deleted, repo: repo)
      end

      it "indicates that the config file is used by version updates is disabled" do
        expect(response).to be_a(DependabotApi::V1::RepositoryStatusResponse)
        expect(response.repository_github_id).to be(repo.github_id)
        expect(response.using_config_file).to be(true)
        expect(response.version_updates_enabled).to be(false)
      end
    end
  end

  describe "resync_config_file" do
    subject(:response) do
      service.call_rpc :ResyncConfigFile, repository_github_id: repository_github_id, owner_github_id: owner_github_id
    end

    let(:repository_github_id) { 42 }
    let(:owner_github_id) { 33 }

    it "returns a not found error if the repository id doesn't exist and auto remediation fails" do
      remediation_action = instance_double(RemediateAccountAndRepoActivation)
      allow(RemediateAccountAndRepoActivation).to receive(:new).
        with(github_repo_id: repository_github_id,
             github_account_id: owner_github_id,
             event_source: "twirp.update_configs_service.resync_config_file",).
        and_return(remediation_action)
      allow(remediation_action).to receive(:run).
        and_raise(RemediateAccountAndRepoActivation::RepoNotAccessible)
      expect(response).to be_a(Twirp::Error)
      expect(response.code).to be(:failed_precondition)
      expect(response.msg).to eql("Repository is not registered with the service.")
    end

    it "returns an empty message if the Repository exists" do
      FactoryBot.create(:repo, github_id: repository_github_id)

      expect(response).to be_a(DependabotApi::V1::ResyncConfigFileResponse)
    end

    it "returns an empty message if the Repository is created via auto remediation" do
      repo = FactoryBot.create(:repo)
      remediation_action = instance_double(RemediateAccountAndRepoActivation)
      allow(RemediateAccountAndRepoActivation).to receive(:new).
        with(github_repo_id: repository_github_id,
             github_account_id: owner_github_id,
             event_source: "twirp.update_configs_service.resync_config_file",).
        and_return(remediation_action)
      allow(remediation_action).to receive(:run).
        and_return(repo)
      expect(response).to be_a(DependabotApi::V1::ResyncConfigFileResponse)
    end

    it "enqueues a job to synchronize the config file from github" do
      repo = FactoryBot.create(:repo, github_id: repository_github_id)

      expect(response).to be_a(DependabotApi::V1::ResyncConfigFileResponse)

      expect(ResyncRepoConfigFileJob).to have_been_enqueued.with(
        account: repo.account,
        repo_name: repo.name,
        repo_github_id: repo.github_id,
        event_source: "twirp.update_configs_service.resync_config_file",
      )
    end
  end

  describe "trigger_update_job" do
    subject(:response) do
      service.call_rpc(:TriggerUpdateJob,
                       repository_github_id: repository_github_id,
                       update_config_id: update_config.id)
    end

    let(:repository_github_id) { 42 }
    let(:repo) { FactoryBot.create(:repo, github_id: repository_github_id) }
    let(:update_config) do
      FactoryBot.create(:update_config, :rate_limited, repo: repo)
    end

    it "creates a new manual_version_update update job" do
      expect { response }.to change(UpdateJob, :count).by(1)
      expect(UpdateJob.last.trigger_type).to eql("manual_version_update")
    end

    it "enqueues a job to check if any open Group PRs need to be refreshed" do
      expect { response }.to have_enqueued_job(RefreshOpenGroupPullRequestsJob).with(
        update_config: update_config,
      )
    end

    it "returns the update job" do
      expect(response).to be_a(DependabotApi::V1::TriggerUpdateJobResponse)
      expect(response.update_job.state).to be(:PENDING)
    end

    it "enqueues the update job" do
      expect do
        response
      end.to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
        with(instance_of(UpdateJob))
    end

    it "marks the repository as active", feature: :inactivity_pausing do
      repo.update(will_pause_at: 30.days.from_now.utc)

      expect { response }.
        to change { repo.reload.will_pause_at }.
        from(within(1.second).of(30.days.from_now.utc)).to(nil)
    end

    context "when the repository doesn't exist" do
      subject(:response) do
        service.call_rpc(:TriggerUpdateJob,
                         repository_github_id: 43,
                         update_config_id: 43)
      end

      it "does not create an update job" do
        expect { response }.not_to change(UpdateJob, :count)
      end

      it "returns an error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:not_found)
        expect(response.msg).to eql("Repository ID not found.")
      end
    end

    context "when the update config doesnt exist" do
      subject(:response) do
        service.call_rpc(:TriggerUpdateJob,
                         repository_github_id: repo.github_id,
                         update_config_id: 43)
      end

      it "does not create an update job" do
        expect { response }.not_to change(UpdateJob, :count)
      end

      it "returns an error" do
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:not_found)
        expect(response.msg).to eql("UpdateConfig ID not found.")
      end
    end

    context "when an update job was triggered recently" do
      before { update_config.update_jobs.create!(trigger_type: :schedule) }

      it "does not create an update job" do
        expect { response }.not_to change(UpdateJob, :count)
      end

      it "does not enqueues a job to check if any open Group PRs need to be refreshed" do
        expect { response }.not_to have_enqueued_job(RefreshOpenGroupPullRequestsJob)
      end

      it "returns the recently triggered update job" do
        expect(response).to be_a(DependabotApi::V1::TriggerUpdateJobResponse)
        expect(response.update_job.id).to be(update_config.last_scheduled_job.id)
      end

      it "still marks the repository as active", feature: :inactivity_pausing do
        repo.update(will_pause_at: 30.days.from_now.utc)

        expect { response }.
          to change { repo.reload.will_pause_at }.
          from(within(1.second).of(30.days.from_now.utc)).to(nil)
      end
    end

    context "when an update job was triggered a while ago but it's still running" do
      before do
        travel_to(5.minutes.ago) do
          update_config.update_jobs.create!(trigger_type: :schedule)
        end
      end

      it "does not create an update job" do
        expect { response }.not_to change(UpdateJob, :count)
      end

      it "does not enqueues a job to check if any open Group PRs need to be refreshed" do
        expect { response }.not_to have_enqueued_job(RefreshOpenGroupPullRequestsJob)
      end

      it "returns the recently triggered update job" do
        expect(response).to be_a(DependabotApi::V1::TriggerUpdateJobResponse)
        expect(response.update_job.id).to be(update_config.last_scheduled_job.id)
      end

      it "still marks the repository as active", feature: :inactivity_pausing do
        repo.update(will_pause_at: 30.days.from_now.utc)

        expect { response }.
          to change { repo.reload.will_pause_at }.
          from(within(1.second).of(30.days.from_now.utc)).to(nil)
      end
    end

    context "when an update job was triggered a while ago and is complete" do
      before do
        travel_to(5.minutes.ago) do
          job = update_config.update_jobs.create!(trigger_type: :manual_version_update)
          job.transition_to!(:enqueued)
          job.transition_to!(:processing)
          job.transition_to!(:processed)
        end
      end

      it "creates a new update job" do
        expect { response }.to change(UpdateJob, :count).by(1)
      end

      it "enqueues a job to check if any open Group PRs need to be refreshed" do
        expect { response }.to have_enqueued_job(RefreshOpenGroupPullRequestsJob).with(
          update_config: update_config,
        )
      end
    end
  end
end
