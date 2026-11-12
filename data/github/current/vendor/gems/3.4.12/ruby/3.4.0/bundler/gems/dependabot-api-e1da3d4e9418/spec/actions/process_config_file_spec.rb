# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProcessConfigFile do
  subject(:action) do
    described_class.new(
      account: account,
      repo_name: repo_name,
      repo_github_id: repo_github_id,
    )
  end

  let(:repo_name) { "dependabot-test" }
  let(:repo_github_id) { 88632334 }
  let(:twirp_settings_client) do
    instance_double(
      GitHub::Twirp::DependabotRepositorySettings,
      get_repository_settings: OpenStruct.new(dependabot_config_file_enabled: true)
    )
  end

  before do
    allow(Dependabot::Application).
      to receive(:dependabot_repository_settings_client).
      and_return(twirp_settings_client)
    allow(SecureRandom).
      to receive(:uuid).
      and_return("1234-5678-90")
  end

  context "for an account that is inactive" do
    let(:account) { FactoryBot.create(:account, :dependabot, :inactive) }

    it "no-ops" do
      expect(FetchConfigFile).not_to receive(:new)
      action.run
    end
  end

  context "for an account that is active" do
    let!(:account) { FactoryBot.create(:account, :dependabot, :active) }

    let(:dummy_config_file_fetcher) do
      instance_double(FetchConfigFile, run: config_file)
    end
    let(:config_file) do
      OpenStruct.new(
        path: ".github/dependabot.yml",
        content: config_file_body,
      )
    end

    before do
      allow(FetchConfigFile).
        to receive(:new).
        and_return(dummy_config_file_fetcher)
    end

    context "when there is no config file" do
      let(:config_file) { nil }

      context "and there is no repo in our database" do
        it "raises an exception" do
          expect { action.run }.to raise_error(ActiveRecord::RecordNotFound, /Couldn't find Repo/)
        end
      end

      context "and there is a repo in our database" do
        let!(:repo) do
          FactoryBot.create(
            :repo,
            account: account,
            name: "dependabot-test",
            github_id: repo_github_id,
            config_file_path: config_file_path,
          )
        end
        let!(:update_config) do
          FactoryBot.create(:update_config, :rate_limited, repo: repo)
        end

        context "not currently using config files" do
          let(:config_file_path) { nil }

          it "no-ops" do
            expect { action.run }.
              not_to change { update_config.current_state(force_reload: true) }
          end

          it "does not mark the repository active" do
            repo.update(will_pause_at: 30.days.from_now.utc)

            expect { action.run }.
              not_to change { repo.reload.will_pause_at }.
              from(within(1.second).of(30.days.from_now.utc))
          end
        end

        context "using config files" do
          let(:config_file_path) { ".github/dependabot.yml" }

          it "deletes the old update config" do
            expect { action.run }.
              to change { repo.reload.using_config_file? }.to(false).
              and change { update_config.current_state(force_reload: true) }.
              to("deleted")
          end

          it "marks the repository as active", feature: :inactivity_pausing do
            repo.update(will_pause_at: 30.days.from_now.utc)

            expect { action.run }.
              to change { repo.reload.will_pause_at }.
              from(within(1.second).of(30.days.from_now.utc)).to(nil)
          end

          context "and the file can't be fetched due to a billing issue" do
            let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
            let(:repo_url) { github_url + "repositories/#{repo_github_id}" }
            let(:file_url) { repo_url + "/contents/.github/dependabot.yml" }
            let(:json_header) { { "Content-Type" => "application/json" } }
            let(:billing_err) do
              fixture("github_responses/forbidden_billing_issue.json")
            end
            let(:repo_details) do
              fixture("github_responses/repo.json")
            end

            before do
              allow(FetchConfigFile).to receive(:new).and_call_original
              allow(GitHubHelpers).
                to receive(:installation_access_token_for).
                and_return("token")
              stub_request(:get, file_url).
                to_return(status: 403, body: billing_err, headers: json_header)
              stub_request(:get, repo_url).
                to_return(status: 200, body: repo_details, headers: json_header)
            end

            it "does not delete the old update config" do
              expect { action.run }.not_to(
                change { update_config.current_state(force_reload: true) }
              )
            end

            it "does not mark the repository active" do
              repo.update(will_pause_at: 30.days.from_now.utc)

              expect { action.run }.
                not_to change { repo.reload.will_pause_at }.
                from(within(1.second).of(30.days.from_now.utc))
            end
          end
        end
      end
    end

    context "when there is a config file" do
      let(:config_file_body) do
        fixture("config_files/minimal_with_vendoring.yml")
      end

      context "and there is no repo in our database" do
        it "raises an exception" do
          expect { action.run }.to raise_error(ActiveRecord::RecordNotFound, /Couldn't find Repo/)
        end
      end

      context "and the repo is already in our database" do
        let!(:repo) do
          FactoryBot.create(
            :repo,
            account: account,
            name: "dependabot-test",
            github_id: repo_github_id,
            config_file_path: config_file_path,
          )
        end

        context "not currently using config files" do
          let(:config_file_path) { nil }

          it "updates the repo and adds the update config to the database" do
            expect { action.run }.
              to change { repo.reload.using_config_file? }.to(true).
              and change(UpdateConfig, :count).by(1)

            update_config = UpdateConfig.last
            expect(update_config.current_state).to eq("rate_limited")
          end

          it "creates an UpdateJob with correct attributes" do
            expect { action.run }.to change(UpdateJob, :count).by(1)

            job = UpdateJob.last
            expect(job.update_config_id).to eq(UpdateConfig.last.id)
            expect(job.trigger_type).to eq("config_file_changed")
            expect(job.enqueue_scheduled_update_id).to eq("1234-5678-90")
          end

          it "marks the repository as active", feature: :inactivity_pausing do
            repo.update(will_pause_at: 30.days.from_now.utc)

            expect { action.run }.
              to change { repo.reload.will_pause_at }.
              from(within(1.second).of(30.days.from_now.utc)).to(nil)
          end

          context "when a similar config file has been deleted" do
            it "resurrects the deleted config file" do
              config_details = {
                package_manager: "bundler",
                directory: "/.",
                target_branch: nil,
                update_schedule: "daily",
              }
              deleted_config_file = FactoryBot.create(:update_config, :deleted, repo: repo, **config_details)

              expect(repo.reload).not_to be_using_config_file

              action.run

              expect(repo.reload).to be_using_config_file
              expect(deleted_config_file.reload).to be_active
            end
          end

          context "with an existing update config" do
            let!(:update_config) do
              FactoryBot.create(
                :update_config, :rate_limited,
                repo: repo,
                package_manager: "bundler",
                directory: "/.",
                target_branch: nil,
                update_schedule: "weekly",
              )
            end

            it "updates the existing update config" do
              expect { action.run }.
                to change { repo.reload.using_config_file? }.to(true).
                and change { update_config.reload.update_schedule }.to("daily")

              expect(update_config.vendor).to eq(true)
              expect(update_config.current_state(force_reload: true)).
                to eq("rate_limited")
            end

            it "triggers a scheduled update run" do
              expect { action.run }.
                to change { UpdateJob.scheduled.count }.by(1)
            end

            # TODO: Remove once we can refresh PRs from the 'main' scheduled job, See:
            #   https://github.com/github/dependabot-updates/pull/4213
            it "triggers a refresh of any open Group PRs" do
              expect { action.run }.
                to have_enqueued_job(RefreshOpenGroupPullRequestsJob).with(update_config: update_config)
            end

            it "enqueues a job to set the default labels" do
              expect { action.run }.
                to have_enqueued_job(UpdateDefaultLabelsJob)
            end

            context "when there was a race and are clashing update configs" do
              before do
                new_update_config = update_config.dup
                new_update_config.directory = "/tmp2"
                new_update_config.save!(validate: false)
                new_update_config = UpdateConfig.find(new_update_config.id)
                new_update_config.transition_to!(:rate_limited)
                new_update_config.update_attribute(:directory, "/.")
              end

              it "cleans up the race" do
                expect { action.run }.
                  to raise_error(ActiveRecord::RecordInvalid).
                  and change { UpdateConfig.active.count }.by(-1)
              end
            end

            context "with a different target branch" do
              let!(:update_config) do
                FactoryBot.create(
                  :update_config, :rate_limited,
                  repo: repo,
                  package_manager: "bundler",
                  directory: "/.",
                  target_branch: "old_branch",
                  update_schedule: "daily",
                )
              end

              it "updates the existing update config" do
                expect { action.run }.
                  to change { repo.reload.using_config_file? }.to(true).
                  and change { update_config.reload.target_branch }.to(nil)

                expect(update_config.current_state(force_reload: true)).
                  to eq("rate_limited")
              end

              context "and multiple update configs" do
                let!(:update_config2) do
                  FactoryBot.create(
                    :update_config, :rate_limited,
                    repo: repo,
                    package_manager: "bundler",
                    directory: "/.",
                    target_branch: "another_old_branch",
                    update_schedule: "daily",
                  )
                end

                it "deleted the existing update configs and creates a new one" do
                  expect { action.run }.
                    to change { repo.reload.using_config_file? }.to(true).
                    and change(UpdateConfig, :count).by(1)

                  expect(update_config.current_state(force_reload: true)).
                    to eq("deleted")
                  expect(update_config2.current_state(force_reload: true)).
                    to eq("deleted")
                end
              end
            end

            context "with an existing ignore condition" do
              let!(:pr_ic) do
                FactoryBot.create(
                  :ignore_condition,
                  update_config: update_config,
                )
              end

              before do
                FactoryBot.create(
                  :ignore_condition,
                  dependency_name: "rails",
                  update_config: update_config,
                  from_config_file: true,
                )
              end

              it "leaves the pr ignore condition alone and deletes the config ignore condition" do
                action.run
                expect(IgnoreCondition.all).to eq([pr_ic])
              end

              context "when switching to using the config file for ignores" do
                let(:config_file_body) do
                  fixture("config_files/optional_properties.yml").
                    gsub(/.*target_branch.*\n/, "")
                end

                context "with an open PR for a now-ignored dependency" do
                  let!(:ignored_pr) do
                    FactoryBot.create(
                      :pull_request,
                      update_config: update_config,
                      dependencies: [
                        {
                          name: "rspec",
                          version: "1.8.0",
                          previous_version: "1.3.0",
                          requirements: [],
                          previous_requirements: [],
                          package_manager: "bundler",
                        },
                      ],
                    )
                  end

                  it "enqueues a job to close the PR" do
                    expect { action.run }.
                      to have_enqueued_job(ClosePullRequestJob).
                      with(
                        pull_request: ignored_pr,
                        reason: "dependency_ignored",
                      )
                  end

                  context "that has been edited" do
                    before { ignored_pr.update!(head_commit_sha: "edited") }

                    it "does not enqueue a job to close the PR" do
                      expect { action.run }.
                        not_to have_enqueued_job(ClosePullRequestJob)
                    end
                  end
                end
              end

              context "when the config file has an equivalent ignore condition" do
                let(:config_file_body) do
                  <<~YAML
                    version: 2
                    updates:
                      - package-ecosystem: "bundler"
                        directory: "/"
                        schedule:
                          interval: "daily"
                        ignore:
                        - dependency-name: "#{pr_ic.dependency_name}"
                          versions: ["#{pr_ic.version_requirement}"]
                  YAML
                end

                it "claims the PR ignore condition" do
                  action.run
                  expect(IgnoreCondition.all).to eq([pr_ic])
                  expect(pr_ic.reload.from_config_file?).to eq(true)
                end
              end
            end

            context "when the config has multiple update-types conditions for the same dependency" do
              let(:config_file_body) do
                <<~YAML
                  version: 2
                  updates:
                    - package-ecosystem: "bundler"
                      directory: "/"
                      schedule:
                        interval: "daily"
                      ignore:
                      - dependency-name: "rails"
                        update-types: ["version-update:semver-patch"]
                      - dependency-name: "rails"
                        update-types: ["version-update:semver-minor"]
                YAML
              end

              it "merges the ignore conditions" do
                action.run
                expect(IgnoreCondition.all.length).to eq(1)
                expect(IgnoreCondition.first.update_types).
                  to eq(["version-update:semver-patch", "version-update:semver-minor"])
              end
            end

            context "with a different insecure-external-code-execution setting" do
              let(:config_file_body) do
                fixture("config_files/bundler_with_registry_with_code_execution_allowed.yml")
              end

              it "updates the existing update config" do
                expect { action.run }.
                  to change { update_config.reload.insecure_external_code_execution }.from(nil).to("allow")
              end
            end

            context "that is for a difference directory" do
              let!(:update_config) do
                FactoryBot.create(
                  :update_config, :rate_limited,
                  repo: repo,
                  package_manager: "bundler",
                  directory: "/dir",
                  target_branch: nil,
                  update_schedule: "daily",
                )
              end

              it "replaces the old update config" do
                expect { action.run }.
                  to change { repo.reload.using_config_file? }.to(true).
                  and change(UpdateConfig, :count).by(1)

                expect(update_config.current_state(force_reload: true)).
                  to eq("deleted")
              end
            end
          end

          context "with an existing update config with a cron schedule" do
            let(:config_file_body) do
              fixture("config_files/with_cron_schedule.yml")
            end

            let!(:update_config) do
              FactoryBot.create(
                :update_config, :rate_limited,
                repo: repo,
                package_manager: "bundler",
                directory: "/.",
                target_branch: nil,
                update_schedule: "weekly",
                update_schedule_cron_expression: nil
              )
            end

            it "updates the existing update config" do
              expect { action.run }.
                to change { repo.reload.using_config_file? }.to(true).
                and change { update_config.reload.update_schedule }.to("cron").
                and change { update_config.reload.update_schedule_cron_expression }.to("0 8 * * 2,4")

              expect(update_config.current_state(force_reload: true)).
                to eq("rate_limited")
            end

            it "triggers a scheduled update run" do
              expect { action.run }.
                to change { UpdateJob.scheduled.count }.by(1)
            end
          end

          context "with an existing update config with a cron schedule statement in modulo format" do
            let(:config_file_body) do
              fixture("config_files/with_cron_mod_schedule.yml")
            end

            let!(:update_config) do
              FactoryBot.create(
                :update_config, :rate_limited,
                repo: repo,
                package_manager: "bundler",
                directory: "/.",
                target_branch: nil,
                update_schedule: "weekly",
                update_schedule_cron_expression: nil
              )
            end

            it "updates the existing update config" do
              expect { action.run }.
                to change { repo.reload.using_config_file? }.to(true).
                and change { update_config.reload.update_schedule }.to("cron").
                and change { update_config.reload.update_schedule_cron_expression }.to("0 8 * * mon%2")

              expect(update_config.current_state(force_reload: true)).
                to eq("rate_limited")
            end

            it "triggers a scheduled update run" do
              expect { action.run }.
                to change { UpdateJob.scheduled.count }.by(1)
            end
          end
        end
      end

      context "and the repo is in our database, but belongs to another account" do
        let(:old_account) do
          FactoryBot.create(:account)
        end

        let!(:repo) do
          FactoryBot.create(
            :repo,
            account: old_account,
            name: "dependabot-test",
            github_id: repo_github_id,
            config_file_path: nil,
          )
        end

        it "transfers the repository to the new account" do
          expect { action.run }.
            to change { repo.reload.account }.from(old_account).to(account)
        end

        it "updates the repo and adds the update config to the database" do
          expect { action.run }.
            to change { repo.reload.using_config_file? }.to(true).
            and change(UpdateConfig, :count).by(1)

          update_config = UpdateConfig.last
          expect(update_config.current_state).to eq("rate_limited")
        end
      end
    end

    context "when enabling auto-merge" do
      let(:config_file_body) { fixture("config_files/auto_merge.yml") }
      let!(:repo) do
        FactoryBot.create(
          :repo,
          account: account,
          name: "dependabot-test",
          github_id: repo_github_id,
          config_file_path: ".github/dependabot.yml",
        )
      end

      it "sets automerge_enabled to true" do
        action.run

        expect(repo.reload.automerge_enabled).to eq(true)
      end
    end

    context "with days-before-merge set" do
      let(:config_file_body) { fixture("config_files/auto_merge_days_before_merge.yml") }
      let!(:repo) do
        FactoryBot.create(
          :repo,
          account: account,
          name: "dependabot-test",
          github_id: repo_github_id,
          config_file_path: ".github/dependabot.yml",
        )
      end

      it "returns days-before-merge" do
        action.run

        expect(repo.reload.automerge_enabled).to eq(true)
        expect(repo.reload.days_before_automerge).to eq(5)
      end
    end

    context "when there is an existing private registry" do
      let(:config_file_body) { fixture("config_files/minimal.yml") }
      let!(:repo) do
        FactoryBot.create(
          :repo,
          account: account,
          name: "dependabot-test",
          github_id: repo_github_id,
          config_file_path: nil,
        )
      end

      it "deletes registry from database" do
        Registry.create!(
          source: repo,
          name: "npm-acme",
          registry_type: "npm_registry",
          credentials: '{"url": "registry.npmjs.org","token":"${{secrets.YE_OLDE_TOKEN}}"}',
        )

        expect { action.run }.
          to change { repo.reload.registries.length }.
          from(1).to(0)
      end
    end

    context "when there is private registry configuration" do
      let(:config_file_body) { fixture("config_files/npm_with_registry.yml") }
      let!(:repo) do
        FactoryBot.create(
          :repo,
          account: account,
          name: "dependabot-test",
          github_id: repo_github_id,
          config_file_path: nil,
        )
      end

      it "creates registry in database" do
        expect { action.run }.
          to change { repo.reload.registries.length }.
          from(0).to(1)
      end

      it "updates existing registry in database" do
        registry = Registry.create!(
          source: repo,
          name: "npm-acme",
          registry_type: "npm_registry",
          credentials: '{"url": "registry.npmjs.org","token":"${{secrets.YE_OLDE_TOKEN}}"}',
        )

        action.run

        updated_credentials = registry.reload.credentials
        expect(updated_credentials).to include("${{secrets.MY_NPM_TOKEN}}")
        expect(updated_credentials).not_to include("YE_OLDE_TOKEN")
      end

      context "when updating a registry" do
        let(:config_file_body) { fixture("config_files/npm_with_registry_with_secret_url.yml") }

        before do
          FactoryBot.create(:registry, :npm_and_yarn, name: "npm-acme", source: repo)
        end

        it "rejects invalid configuration" do
          expect { action.run }.to change(ConfigFileError, :count).by(1)

          config_file_error = ConfigFileError.last

          expect(config_file_error.error_type).to eql("invalid_config_file")
        end
      end

      it "deletes existing registry in database" do
        Registry.create!(
          source: repo,
          name: "ye-olde-npm",
          registry_type: "npm_registry",
          credentials: '{"url": "registry.npmjs.org","token":"${{secrets.MY_NPM_TOKEN}}"}',
        )

        action.run

        registry_names = repo.reload.registries.pluck(:name)
        expect(registry_names).to include("npm-acme")
        expect(registry_names).not_to include("ye-old-npm")
      end
    end

    context "when group order is enabled" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              schedule:
                interval: "daily"
              groups:
                my-update-group:
                  patterns:
                    - "rails"
                    - "active*"
                my-other-update-group:
                  patterns:
                    - "other"
                    - "rubo*"
        YAML
      end

      it "adds group order when groups are created" do
        FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)
        expect { action.run }.to change(DependencyGroup, :count).by(2)

        group = DependencyGroup.first
        expect(group.name).to eq("my-update-group")
        expect(group.rules).to eq({ "patterns" => %w(rails active*) })
        expect(group.sort_order).to eq(0)

        group2 = DependencyGroup.last
        expect(group2.name).to eq("my-other-update-group")
        expect(group2.rules).to eq({ "patterns" => %w(other rubo*) })
        expect(group2.sort_order).to eq(1)
      end

      # rubocop:disable RSpec/ExampleLength
      it "adds group order when groups are updated" do
        repo = FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)

        update_config = FactoryBot.create(:update_config, :active, repo: repo, directory: "/.")
        FactoryBot.create(
          :dependency_group,
          update_config: update_config,
          name: "my-other-update-group",
          rules: { "patterns": ["other", "rubo*"] }
        )

        existing_group = DependencyGroup.first
        expect(existing_group.name).to eq("my-other-update-group")
        expect(existing_group.rules).to eq({ "patterns" => %w(other rubo*) })
        expect(existing_group.sort_order).to eq(nil)

        expect { action.run }.to change(DependencyGroup, :count).by(1)

        group = DependencyGroup.last
        expect(group.name).to eq("my-update-group")
        expect(group.rules).to eq({ "patterns" => %w(rails active*) })
        expect(group.sort_order).to eq(0)

        group2 = DependencyGroup.first
        expect(group2.name).to eq("my-other-update-group")
        expect(group2.rules).to eq({ "patterns" => %w(other rubo*) })
        expect(group2.sort_order).to eq(1)
      end
      # rubocop:enable RSpec/ExampleLength

      # rubocop:disable RSpec/ExampleLength
      context "when the groups are rearranged" do
        let(:config_file_body) do
          <<~YAML
            version: 2
            updates:
              - package-ecosystem: "bundler"
                directory: "/"
                schedule:
                  interval: "daily"
                groups:
                  my-other-update-group:
                    patterns:
                      - "other"
                      - "rubo*"
                  my-update-group:
                    patterns:
                      - "rails"
                      - "active*"
                  yet-another-update-group:
                    patterns:
                      - "yolo"
                      - "chef*"
          YAML
        end

        it "updates the group order to match" do
          repo = FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)

          update_config = FactoryBot.create(:update_config, :active, repo: repo, directory: "/.")
          FactoryBot.create(
            :dependency_group,
            update_config: update_config,
            name: "my-update-group",
            rules: { "patterns": ["rails", "active*"] },
            sort_order: 2
          )
          FactoryBot.create(
            :dependency_group,
            update_config: update_config,
            name: "my-other-update-group",
            rules: { "patterns": ["other", "rubo*"] },
            sort_order: 1
          )
          FactoryBot.create(
            :dependency_group,
            update_config: update_config,
            name: "yet-another-update-group",
            rules: { "patterns": ["yolo", "chef*"] },
            sort_order: 0
          )
          existing_group = DependencyGroup.first
          expect(existing_group.name).to eq("my-update-group")
          expect(existing_group.rules).to eq({ "patterns" => %w(rails active*) })
          expect(existing_group.sort_order).to eq(2)

          existing_group2 = DependencyGroup.second
          expect(existing_group2.name).to eq("my-other-update-group")
          expect(existing_group2.rules).to eq({ "patterns" => %w(other rubo*) })
          expect(existing_group2.sort_order).to eq(1)

          existing_group3 = DependencyGroup.last
          expect(existing_group3.name).to eq("yet-another-update-group")
          expect(existing_group3.rules).to eq({ "patterns" => %w(yolo chef*) })
          expect(existing_group3.sort_order).to eq(0)

          expect(DependencyGroup.count).to eq(3)
          expect { action.run }.to change(DependencyGroup, :count).by(0)

          group = DependencyGroup.first
          expect(group.name).to eq("my-update-group")
          expect(group.rules).to eq({ "patterns" => %w(rails active*) })
          expect(group.sort_order).to eq(1)

          group2 = DependencyGroup.second
          expect(group2.name).to eq("my-other-update-group")
          expect(group2.rules).to eq({ "patterns" => %w(other rubo*) })
          expect(group2.sort_order).to eq(0)

          group3 = DependencyGroup.last
          expect(group3.name).to eq("yet-another-update-group")
          expect(group3.rules).to eq({ "patterns" => %w(yolo chef*) })
          expect(group3.sort_order).to eq(2)
        end
      end
      # rubocop:enable RSpec/ExampleLength
    end

    context "when there is applies-to in the configuration" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              schedule:
                interval: "daily"
              groups:
                my-update-group:
                  applies-to: "security-updates"
                  patterns:
                    - "rails"
                    - "active*"
        YAML
      end

      it "creates the group" do
        FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)
        expect { action.run }.to change(DependencyGroup, :count).by(1)

        group = DependencyGroup.last
        expect(group.name).to eq("my-update-group")
        expect(group.rules).to eq({ "patterns" => %w(rails active*) })
        expect(group.applies_to).to eq("security-updates")
      end

      # rubocop:disable RSpec/ExampleLength
      it "updates groups when the applies-to config has changed" do
        repo = FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)

        update_config = FactoryBot.create(:update_config, :active, repo: repo, directory: "/.")
        FactoryBot.create(
          :dependency_group,
          update_config: update_config,
          name: "my-update-group",
          rules: { "patterns": ["rails", "active*"] }
        )

        group = DependencyGroup.last
        expect(group.name).to eq("my-update-group")
        expect(group.rules).to eq({ "patterns" => %w(rails active*) })
        expect(group.applies_to).to eq("version-updates")

        expect { action.run }.not_to change { update_config.reload.dependency_groups.count }

        group = DependencyGroup.last
        expect(group.name).to eq("my-update-group")
        expect(group.rules).to eq({ "patterns" => %w(rails active*) })
        expect(group.applies_to).to eq("security-updates")
      end
      # rubocop:enable RSpec/ExampleLength

      # rubocop:disable RSpec/ExampleLength
      it "does not modify groups whose properties have not changed" do
        repo = FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)

        # duplicate group that's the same as the one in the config file body
        update_config = FactoryBot.create(:update_config, :active, repo: repo, directory: "/.")
        FactoryBot.create(
          :dependency_group,
          update_config: update_config,
          name: "my-update-group",
          rules: { "patterns": ["rails", "active*"] },
          applies_to: "security-updates"
        )

        original_group = DependencyGroup.last
        expect(original_group.name).to eq("my-update-group")
        expect(original_group.rules).to eq({ "patterns" => %w(rails active*) })
        expect(original_group.applies_to).to eq("security-updates")

        expect { action.run }.not_to change { update_config.reload.dependency_groups.count }

        group = DependencyGroup.last
        expect(group.name).to eq("my-update-group")
        # The group was not modified
        expect(group.rules).to eq({ "patterns" => %w(rails active*) })
        expect(group.applies_to).to eq("security-updates")
        expect(original_group).to eq(group)
      end
      # rubocop:enable RSpec/ExampleLength

      # rubocop:disable RSpec/ExampleLength
      it "replaces groups on update" do
        repo = FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)
        update_config = FactoryBot.create(:update_config, :active, repo: repo, directory: "/.")
        FactoryBot.create(
          :dependency_group,
          update_config: update_config,
          name: "your-update-group",
          rules: { "patterns": ["rails", "active*"] },
        )

        group = DependencyGroup.last
        expect(group.name).to eq("your-update-group")
        expect(group.rules).to eq({ "patterns" => %w(rails active*) })
        expect(group.applies_to).to eq("version-updates")

        expect { action.run }.not_to change { update_config.reload.dependency_groups.count }

        group = DependencyGroup.last
        expect(group.name).to eq("my-update-group")
        expect(group.rules).to eq({ "patterns" => %w(rails active*) })
        expect(group.applies_to).to eq("security-updates")
      end
      # rubocop:enable RSpec/ExampleLength
    end

    context "when there are dependency groups in the configuration" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              schedule:
                interval: "daily"
              groups:
                my-update-group:
                  patterns:
                    - "rails"
                    - "active*"
        YAML
      end

      it "creates the group" do
        FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)
        expect { action.run }.to change(DependencyGroup, :count).by(1)

        group = DependencyGroup.last
        expect(group.name).to eq("my-update-group")
        expect(group.rules).to eq({ "patterns" => %w(rails active*) })
      end

      it "updates groups when the rules have changed" do
        repo = FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)

        # group with the same name but different rules than the group in the config file body
        update_config = FactoryBot.create(:update_config, :active, repo: repo, directory: "/.")
        FactoryBot.create(
          :dependency_group,
          update_config: update_config,
          name: "my-update-group",
          rules: { "patterns": ["hanami", "dry-*"] }
        )

        group = DependencyGroup.last
        expect(group.name).to eq("my-update-group")
        expect(group.rules).to eq({ "patterns" => %w(hanami dry-*) })

        expect { action.run }.not_to change { update_config.reload.dependency_groups.count }

        group = DependencyGroup.last
        expect(group.name).to eq("my-update-group")
        # The group was updated to use the new patterns
        expect(group.rules).to eq({ "patterns" => %w(rails active*) })
      end

      # rubocop:disable RSpec/ExampleLength
      it "does not modify groups whose rules have not changed" do
        repo = FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)

        # duplicate group that's the same as the one in the config file body
        update_config = FactoryBot.create(:update_config, :active, repo: repo, directory: "/.")
        FactoryBot.create(
          :dependency_group,
          update_config: update_config,
          name: "my-update-group",
          rules: { "patterns": ["rails", "active*"] }
        )

        original_group = DependencyGroup.last
        expect(original_group.name).to eq("my-update-group")
        expect(original_group.rules).to eq({ "patterns" => %w(rails active*) })

        expect { action.run }.not_to change { update_config.reload.dependency_groups.count }

        group = DependencyGroup.last
        expect(group.name).to eq("my-update-group")
        # The group was not modified
        expect(group.rules).to eq({ "patterns" => %w(rails active*) })
        expect(original_group).to eq(group)
      end
      # rubocop:enable RSpec/ExampleLength

      it "replaces groups on update" do
        repo = FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)
        update_config = FactoryBot.create(:update_config, :active, repo: repo, directory: "/.")
        FactoryBot.create(
          :dependency_group,
          update_config: update_config,
          name: "your-update-group",
          rules: { "patterns": ["hanami", "dry-*"] }
        )

        group = DependencyGroup.last
        expect(group.name).to eq("your-update-group")
        expect(group.rules).to eq({ "patterns" => %w(hanami dry-*) })

        expect { action.run }.not_to change { update_config.reload.dependency_groups.count }

        group = DependencyGroup.last
        expect(group.name).to eq("my-update-group")
        expect(group.rules).to eq({ "patterns" => %w(rails active*) })
      end

      it "does not modify any logically deleted groups that already exist" do
        repo = FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)
        update_config = FactoryBot.create(:update_config, :active, repo: repo, directory: "/.")
        deleted_group = FactoryBot.create(
          :dependency_group,
          update_config: update_config,
          name: "your-update-group",
          rules: { "patterns": ["hanami", "dry-*"] },
          deleted_at: 1.week.ago
        )

        expect { action.run }.not_to change { deleted_group.reload.deleted_at }
      end

      it "enqueues cleanup jobs for any groups that are deleted" do
        repo = FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)
        update_config = FactoryBot.create(:update_config, :active, repo: repo, directory: "/.")
        old_group = FactoryBot.create(
          :dependency_group,
          update_config: update_config,
          name: "your-update-group",
          rules: { "patterns": ["hanami", "dry-*"] }
        )

        expect { action.run }.to change { old_group.reload.deleted_at }.from(nil)

        expect(CleanupDependencyGroupPullRequestsJob).to have_been_enqueued.with(old_group.id)
      end

      context "when all dependency groups are removed" do
        let(:config_file_body) do
          <<~YAML
            version: 2
            updates:
              - package-ecosystem: "bundler"
                directory: "/"
                schedule:
                  interval: "daily"
          YAML
        end

        it "enqueues cleanup jobs for any groups that are deleted" do
          repo = FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)
          update_config = FactoryBot.create(:update_config, :active, repo: repo, directory: "/.")
          old_group = FactoryBot.create(
            :dependency_group,
            update_config: update_config,
            name: "your-update-group",
            rules: { "patterns": ["hanami", "dry-*"] }
          )

          expect { action.run }.to change { old_group.reload.deleted_at }.from(nil)

          expect(CleanupDependencyGroupPullRequestsJob).to have_been_enqueued.with(old_group.id)
        end
      end
    end

    context "when there is a dependency group for development dependencies" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              schedule:
                interval: "daily"
              groups:
                dev-dependencies:
                  dependency-type: "development"
        YAML
      end

      it "creates the group" do
        FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)
        expect { action.run }.to change(DependencyGroup, :count).by(1)

        group = DependencyGroup.last
        expect(group.name).to eq("dev-dependencies")
        expect(group.rules).to eq({ "dependency-type" => "development" })
      end
    end

    context "when the groups key is present but empty" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              schedule:
                interval: "daily"
              groups:
        YAML
      end

      before do
        FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)
      end

      it "does not create any groups" do
        expect { action.run }.not_to change(DependencyGroup, :count)
      end

      it "errors that the groups propery is not an object" do
        expect { action.run }.to change(ConfigFileError, :count).by(1)

        error_msg = ConfigFileError.last.error_details["message"]
        expect(error_msg).to include("type null did not match the following type: object")
      end
    end

    context "when a group is an incorrect data type" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              schedule:
                interval: "daily"
              groups:
                my-new-group:
                  - "foooooo"
        YAML
      end

      before do
        FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)
      end

      it "does not create any groups" do
        expect { action.run }.not_to change(DependencyGroup, :count)
      end

      it "errors that the groups propery is not an object" do
        expect { action.run }.to change(ConfigFileError, :count).by(1)

        error_msg = ConfigFileError.last.error_details["message"]
        expect(error_msg).to include("type array did not match the following type: object")
      end
    end

    context "when a group has only exclude-patterns defined" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              schedule:
                interval: "daily"
              groups:
                my-new-group:
                  exclude-patterns:
                    - foo
                    - bar
        YAML
      end

      before do
        FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)
      end

      it "creates the group" do
        expect { action.run }.to change(DependencyGroup, :count).by(1)
      end
    end

    context "when the groups have an empty pattern key" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              schedule:
                interval: "daily"
              groups:
                my-new-group:
                  patterns:
        YAML
      end

      before do
        FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)
      end

      it "does not create any groups" do
        expect { action.run }.not_to change(DependencyGroup, :count)
      end

      it "errors that the groups propery is not an object" do
        expect { action.run }.to change(ConfigFileError, :count).by(1)

        error_msg = ConfigFileError.last.error_details["message"]
        expect(error_msg).to include("type null did not match the following type: array")
      end
    end

    context "when there is an ignore condition that specifies update types without version requirements" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              schedule:
                interval: "daily"
              ignore:
              - dependency-name: "rails"
                update-types: ["version-update:semver-patch"]
        YAML
      end

      it "creates the ignore condition" do
        FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)
        expect { action.run }.to change(IgnoreCondition, :count).by(1)
        ic = IgnoreCondition.last
        expect(ic.version_requirement).to be(nil)
        expect(ic.update_types).to eq(["version-update:semver-patch"])
      end
    end

    context "when there is an ignore condition that specifies update types and version requirements" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              schedule:
                interval: "daily"
              ignore:
              - dependency-name: "rails"
                versions: ["4.x"]
                update-types: ["version-update:semver-patch"]
        YAML
      end
      let!(:repo) do
        FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)
      end

      it "creates one ignore condition for the update types and one for the version requirements" do
        expect { action.run }.to change(IgnoreCondition, :count).by(2)

        ignore_conditions = repo.update_configs.first.ignore_conditions.where(dependency_name: "rails").to_a
        expect(ignore_conditions.count do |ic|
                 ic.version_requirement.nil? && ic.update_types == ["version-update:semver-patch"]
               end).to eq(1)
        expect(ignore_conditions.count { |ic| ic.version_requirement == "4.x" && ic.update_types.nil? }).to eq(1)
      end
    end

    context "when there is an ignore condition that specifies version requirements without update types" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              schedule:
                interval: "daily"
              ignore:
              - dependency-name: "rails"
                versions: ["4.x"]
        YAML
      end

      it "creates the ignore condition" do
        FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)
        expect { action.run }.to change(IgnoreCondition, :count).by(1)
        ic = IgnoreCondition.last
        expect(ic.version_requirement).to eq("4.x")
        expect(ic.update_types).to be(nil)
      end
    end

    context "when there is an ignore condition that specifies update types matching an open pull request" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              schedule:
                interval: "daily"
              ignore:
              - dependency-name: "rspec"
                update-types: ["version-update:semver-patch"]
        YAML
      end
      let!(:repo) do
        FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)
      end
      let!(:update_config) do
        FactoryBot.create(
          :update_config, :rate_limited,
          repo: repo,
          package_manager: "bundler",
          directory: "/.",
          target_branch: nil,
          update_schedule: "daily",
        )
      end
      let(:config_file_path) { ".github/dependabot.yml" }

      let!(:ignored_pr) do
        FactoryBot.create(
          :pull_request,
          update_config: update_config,
          dependencies: [
            {
              name: "rspec",
              version: "1.3.1",
              previous_version: "1.3.0",
              requirements: [],
              previous_requirements: [],
              package_manager: "bundler",
            },
          ],
        )
      end

      it "enqueues a job to close the PR" do
        expect { action.run }.
          to have_enqueued_job(ClosePullRequestJob).
          with(
            pull_request: ignored_pr,
            reason: "dependency_ignored",
          )
      end

      context "when the pull request is a security update" do
        let!(:update_job) do
          FactoryBot.create(:update_job, :security, update_config: update_config)
        end

        before do
          ignored_pr.update!(update_job: update_job)
        end

        it "does not close the PR" do
          expect { action.run }.not_to have_enqueued_job(ClosePullRequestJob)
        end
      end
    end

    context "when the config disables version updates" do
      let(:config_file_body) { fixture("config_files/open_pr_limit_zero.yml") }

      it "doesn't trigger a scheduled update run" do
        FactoryBot.create(
          :repo,
          account: account,
          name: "dependabot-test",
          github_id: repo_github_id,
          config_file_path: nil,
        )

        expect { action.run }.
          not_to change { UpdateJob.scheduled.count }
      end
    end

    context "when the config has a glob directory" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directories:
                - "**/*"
              schedule:
                interval: "daily"
        YAML
      end

      it "creates a config with a normalized glob directory" do
        repo = FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)
        repo.enable_feature(:multi_directory_updates)

        expect { action.run }.to change(UpdateConfig, :count).by(1)

        expect(UpdateConfig.last.directories).to eq(["/**/*"])
      end
    end

    context "when a config is not valid" do
      let(:config_file_body) do
        <<~YAML
          I messed this up
        YAML
      end

      let!(:repo) { FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id) }

      it "does not create any configs" do
        expect { action.run }.not_to change(UpdateConfig, :count)
      end

      it "errors that the config is not valid" do
        expect { action.run }.to change(ConfigFileError, :count).by(1)

        error_msg = ConfigFileError.last.error_details["message"]
        expect(error_msg).to include("Top level entity must be an Object, not a String")
      end

      it "indicates a config file is used so we can display errors" do
        action.run

        repo.reload
        expect(repo.using_config_file?).to eq(true)
      end
    end

    context "when directories is used" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directories: ["backend", "frontend"]
              schedule:
                interval: "daily"
        YAML
      end

      it "creates a config with directories" do
        FactoryBot.create(:repo, account: account, name: repo_name, github_id: repo_github_id)

        expect { action.run }.to change(UpdateConfig, :count).by(1)

        expect(UpdateConfig.last.directories).to eq(["/backend", "/frontend"])
      end
    end
  end

  describe "checking Dependabot settings in the monolith" do
    let!(:account) { FactoryBot.create(:account, :dependabot, :active) }

    let!(:repo) do
      FactoryBot.create(
        :repo,
        account: account,
        name: "dependabot-test",
        github_id: repo_github_id,
        config_file_path: config_file_path,
      )
    end

    let(:dummy_config_file_fetcher) do
      instance_double(FetchConfigFile, run: config_file)
    end

    let(:config_file) do
      OpenStruct.new(
        path: ".github/dependabot.yml",
        content: config_file_body,
      )
    end

    let(:config_file_body) do
      fixture("config_files/minimal_with_vendoring.yml")
    end

    before do
      allow(FetchConfigFile).
        to receive(:new).
        and_return(dummy_config_file_fetcher)
    end

    context "the repository is already using a config file" do
      let(:config_file_path) { ".github/dependabot.yml" }

      it "does not check the Dependabot settings in the monolith" do
        expect(twirp_settings_client).not_to receive(:get_repository_settings)

        action.run
      end
    end

    context "the repository is not already using a config file" do
      let(:config_file_path) { nil }

      it "processes the file if dependabot_config_file_enabled is true in the monolith" do
        allow(twirp_settings_client).to receive(:get_repository_settings).
          with(repo) { OpenStruct.new(dependabot_config_file_enabled: true) }

        expect { action.run }.to change(UpdateConfig, :count).from(0).to(1)
      end

      it "does not process the file if dependabot_config_file_enabled is false in the monolith" do
        allow(twirp_settings_client).to receive(:get_repository_settings).
          with(repo) { OpenStruct.new(dependabot_config_file_enabled: false) }

        expect { action.run }.not_to change(UpdateConfig, :count).from(0)
      end
    end

    context "there is an error communicating with the monolith" do
      let(:config_file_path) { nil }

      it "re-raises the error" do
        allow(twirp_settings_client).to receive(:get_repository_settings).
          with(repo).and_raise(GitHub::Twirp::DependabotRepositorySettings::Error, "🔥")

        expect { action.run }.to raise_error(GitHub::Twirp::DependabotRepositorySettings::Error, "🔥")
      end
    end
  end

  context "when there's a security update config" do
    let(:account) { FactoryBot.create(:account, :dependabot, :active) }
    let(:repo) do
      FactoryBot.create(
        :repo,
        account: account,
        name: "dependabot-test",
        github_id: repo_github_id,
        config_file_path: ".github/dependabot.yml",
      )
    end
    let!(:existing_update_config) do
      FactoryBot.create(
        :update_config,
        :rate_limited,
        repo: repo,
        package_manager: "bundler",
        directory: "/.",
        target_branch: nil,
        update_schedule: "never"
      )
    end
    let(:fetch_config_file) { instance_double(FetchConfigFile, run: config_file) }
    let(:config_file) do
      OpenStruct.new(
        path: ".github/dependabot.yml",
        content: config_file_body,
      )
    end

    before do
      allow(FetchConfigFile).to receive(:new).and_return(fetch_config_file)
    end

    context "and a config file is added to the repo with the same directory" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              schedule:
                interval: "daily"
        YAML
      end

      it "updates the existing config" do
        expect { action.run }.to change(UpdateConfig, :count).by(0)

        existing_update_config.reload
        expect(existing_update_config.current_state).to eq("rate_limited")
        expect(existing_update_config.update_schedule).to eq("daily")
      end
    end

    context "and a config file is added to the repo with the same directory, and also another update" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              schedule:
                interval: "daily"
            - package-ecosystem: "bundler"
              directory: "/backend"
              schedule:
                interval: "daily"
        YAML
      end

      it "updates the existing config" do
        expect { action.run }.to change(UpdateConfig, :count).by(1)

        expect(UpdateConfig.active.count).to eq(2)
        expect(UpdateConfig.active.last.directory).to eq("/backend")
        existing_update_config.reload
        expect(existing_update_config.current_state).to eq("rate_limited")
        expect(existing_update_config.update_schedule).to eq("daily")
      end
    end

    context "and a config file is added that uses a different directory" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directory: "/backend"
              schedule:
                interval: "daily"
        YAML
      end

      it "creates a new UpdateConfig and deletes the security config" do
        expect { action.run }.to change(UpdateConfig, :count).by(1)

        expect(UpdateConfig.active.count).to eq(1)
        expect(UpdateConfig.active.last.directory).to eq("/backend")
        expect(existing_update_config.reload.current_state).to eq("deleted")
        expect(existing_update_config.directory).to eq("/.")
      end
    end

    context "and a config file is added that uses directories that includes the directory in the security config" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directories: ["/", "frontend"]
              schedule:
                interval: "daily"
        YAML
      end

      it "creates a new UpdateConfig and deletes the security config" do
        expect { action.run }.to change(UpdateConfig, :count).by(1)

        expect(UpdateConfig.active.count).to eq(1)
        expect(UpdateConfig.active.last.directories).to eq(["/.", "/frontend"])
        expect(existing_update_config.reload.current_state).to eq("deleted")
        expect(existing_update_config.directory).to eq("/.")
      end
    end

    context "and a config file is added that uses a glob that overlaps the security config" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directories: ["**/*"]
              schedule:
                interval: "daily"
        YAML
      end

      it "creates a new UpdateConfig and deletes the security config" do
        expect { action.run }.to change(UpdateConfig, :count).by(1)

        expect(UpdateConfig.active.count).to eq(1)
        expect(UpdateConfig.active.last.directories).to eq(["/**/*"])
        expect(existing_update_config.reload.current_state).to eq("deleted")
        expect(existing_update_config.directory).to eq("/.")
      end
    end
  end

  context "when there's a multi-directory security update config" do
    let(:account) { FactoryBot.create(:account, :dependabot, :active) }
    let(:repo) do
      FactoryBot.create(
        :repo,
        account: account,
        name: "dependabot-test",
        github_id: repo_github_id,
        config_file_path: ".github/dependabot.yml",
      )
    end
    let!(:existing_update_config) do
      FactoryBot.create(
        :update_config,
        :rate_limited,
        repo: repo,
        package_manager: "bundler",
        directory: nil,
        directories: ["/.", "/frontend"],
        target_branch: nil,
        update_schedule: "never"
      )
    end
    let(:fetch_config_file) { instance_double(FetchConfigFile, run: config_file) }
    let(:config_file) do
      OpenStruct.new(
        path: ".github/dependabot.yml",
        content: config_file_body,
      )
    end

    before do
      allow(FetchConfigFile).to receive(:new).and_return(fetch_config_file)
    end

    context "and a config file is added to the repo with one of the same directories" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              schedule:
                interval: "daily"
        YAML
      end

      it "deletes the existing config" do
        expect { action.run }.to change(UpdateConfig, :count).by(1)

        existing_update_config.reload
        expect(existing_update_config.current_state).to eq("deleted")
      end
    end

    context "and a config file is added that uses the same directories" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directories: ["/", "frontend"]
              schedule:
                interval: "daily"
        YAML
      end

      it "updates the security config" do
        expect { action.run }.to change(UpdateConfig, :count).by(0)

        expect(UpdateConfig.active.count).to eq(1)
        expect(UpdateConfig.active.last.directories).to eq(["/.", "/frontend"])
        expect(existing_update_config.reload.current_state).to eq("rate_limited")
      end
    end

    context "and a config file is added that uses the same directories in a different order" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directories: ["frontend", "/"]
              schedule:
                interval: "daily"
        YAML
      end

      it "keeps directories sorted" do
        expect { action.run }.to change(UpdateConfig, :count).by(0)

        expect(UpdateConfig.active.count).to eq(1)
        expect(UpdateConfig.active.last.directories).to eq(["/.", "/frontend"])
        expect(existing_update_config.reload.current_state).to eq("rate_limited")
      end
    end

    context "and a config file is added that uses different directories" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directories: ["/hello", "/world"]
              schedule:
                interval: "daily"
        YAML
      end

      it "updates the security config" do
        expect { action.run }.to change(UpdateConfig, :count).by(0)

        expect(UpdateConfig.active.count).to eq(1)
        expect(existing_update_config.reload.directories).to eq(["/hello", "/world"])
      end
    end

    context "and a config file is added that has multiple directories entries" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            # This should update the security config
            - package-ecosystem: "bundler"
              directories: ["/.", "/frontend"]
              schedule:
                interval: "daily"
            # This should create a new update config
            - package-ecosystem: "bundler"
              directories: ["/hello", "/world"]
              schedule:
                interval: "daily"
        YAML
      end

      it "updates the security config and creates a new update config" do
        expect { action.run }.to change(UpdateConfig, :count).by(1)

        expect(UpdateConfig.active.count).to eq(2)
        expect(UpdateConfig.active.last.directories).to eq(["/hello", "/world"])
        expect(existing_update_config.reload.current_state).to eq("rate_limited")
        expect(existing_update_config.directories).to eq(["/.", "/frontend"])
        expect(existing_update_config.update_schedule).to eq("daily")
      end
    end

    context "and a config file is added that splits up the directories" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directories: ["/.", "/hello"]
              schedule:
                interval: "daily"
            - package-ecosystem: "bundler"
              directories: ["/world", "/frontend"]
              schedule:
                interval: "daily"
        YAML
      end

      it "creates two new new update configs" do
        expect { action.run }.to change(UpdateConfig, :count).by(2)

        expect(UpdateConfig.active.count).to eq(2)
        expect(UpdateConfig.active.map(&:directories)).to eq([
                                                               ["/.", "/hello"],
                                                               ["/frontend", "/world"],
                                                             ])
      end
    end
  end

  context "when there's multiple single-directory security update configs" do
    let(:account) { FactoryBot.create(:account, :dependabot, :active) }
    let(:repo) do
      FactoryBot.create(
        :repo,
        account: account,
        name: "dependabot-test",
        github_id: repo_github_id,
        config_file_path: ".github/dependabot.yml",
      )
    end
    let!(:existing_update_config1) do
      FactoryBot.create(
        :update_config,
        :rate_limited,
        repo: repo,
        package_manager: "bundler",
        directory: "/.",
        target_branch: nil,
        update_schedule: "never"
      )
    end
    let!(:existing_update_config2) do
      FactoryBot.create(
        :update_config,
        :rate_limited,
        repo: repo,
        package_manager: "bundler",
        directory: "/frontend",
        target_branch: nil,
        update_schedule: "never"
      )
    end
    let(:fetch_config_file) { instance_double(FetchConfigFile, run: config_file) }
    let(:config_file) do
      OpenStruct.new(
        path: ".github/dependabot.yml",
        content: config_file_body,
      )
    end

    before do
      allow(FetchConfigFile).to receive(:new).and_return(fetch_config_file)
    end

    context "and a config file is added that has multiple directories entries" do
      let(:config_file_body) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directories: ["/.", "/frontend"]
              schedule:
                interval: "daily"
        YAML
      end

      it "deletes the security configs and creates a new update config" do
        expect { action.run }.to change(UpdateConfig, :count).by(1)

        expect(UpdateConfig.active.count).to eq(1)
        expect(UpdateConfig.active.last.directories).to eq(["/.", "/frontend"])
        expect(existing_update_config1.reload.current_state).to eq("deleted")
        expect(existing_update_config2.reload.current_state).to eq("deleted")
      end
    end
  end

  context "with the multi-ecosystem feature flag enabled" do
    let(:account) { FactoryBot.create(:account, :dependabot, :active) }
    let(:repo) do
      FactoryBot.create(
        :repo,
        account: account,
        name: repo_name,
        github_id: repo_github_id,
        config_file_path: ".github/dependabot.yml",
      )
    end

    let(:fetch_config_file) { instance_double(FetchConfigFile, run: config_file) }
    let(:config_file) do
      OpenStruct.new(
        path: ".github/dependabot.yml",
        content: config_file_body,
      )
    end
    let(:config_file_body) do
      <<~YAML
        version: 2

        multi-ecosystem-groups:
          rails-and-rspec:
            schedule:
              interval: "daily"

        updates:
          - package-ecosystem: "bundler"
            directory: "/"
            patterns:
              - "rails*"
              - "rspec*"
            multi-ecosystem-group: rails-and-rspec
      YAML
    end

    before do
      allow(FetchConfigFile).to receive(:new).and_return(fetch_config_file)

      repo.enable_feature(:multi_ecosystems)
    end

    it "creates a config with the correct package ecosystems" do
      expect { action.run }.to change(UpdateConfig, :count).by(1)

      update_config = UpdateConfig.last

      expect(update_config.multi_ecosystem_config).to be_present
      expect(update_config.multi_ecosystem_config.name).to eq("rails-and-rspec")

      expect(update_config.package_manager).to eq("bundler")
      expect(update_config.update_schedule).to eq("daily")
      expect(update_config.dependency_groups.count).to eq(1)
      expect(update_config.dependency_groups.first.rules).to eq({ "patterns" => %w(rails* rspec*) })
      expect(update_config.dependency_groups.first.name).to eq("rails-and-rspec")
    end

    context "when the config file has multiple multi-ecosystem configs" do
      let(:config_file_body) do
        <<~YAML
          version: 2

          multi-ecosystem-groups:
            rails-and-rspec:
              schedule:
                interval: "daily"

            playwright:
              schedule:
                interval: "daily"

          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              patterns:
                - "rails*"
                - "rspec*"
              multi-ecosystem-group: "rails-and-rspec"

            - package-ecosystem: "npm"
              directory: "/"
              patterns: ["react*"]
              multi-ecosystem-group: "rails-and-rspec"

            - package-ecosystem: "bundler"
              directory: "/"
              patterns: ["playwright-ruby-client"]
              multi-ecosystem-group: "playwright"

            - package-ecosystem: "npm"
              directory: "/"
              patterns: ["playwright"]
              multi-ecosystem-group: "playwright"
        YAML
      end

      it "creates configs with the correct package ecosystems" do
        expect { action.run }.to change(UpdateConfig, :count).by(4)

        rails_multi_ecosystem_config = repo.multi_ecosystem_configs.find_by(name: "rails-and-rspec")

        expect(rails_multi_ecosystem_config).to be_present
        expect(rails_multi_ecosystem_config.name).to eq("rails-and-rspec")

        expect(rails_multi_ecosystem_config.update_configs.count).to eq(2)
        expect(rails_multi_ecosystem_config.update_configs.map(&:package_manager)).to eq(%w(bundler npm_and_yarn))
        expect(rails_multi_ecosystem_config.update_configs.map(&:update_schedule)).to eq(%w(daily daily))

        playwright_multi_ecosystem_config = repo.multi_ecosystem_configs.find_by(name: "playwright")

        expect(playwright_multi_ecosystem_config).to be_present
        expect(playwright_multi_ecosystem_config.name).to eq("playwright")

        expect(playwright_multi_ecosystem_config.update_configs.count).to eq(2)
        expect(playwright_multi_ecosystem_config.update_configs.map(&:package_manager)).to eq(%w(bundler npm_and_yarn))
        expect(playwright_multi_ecosystem_config.update_configs.map(&:update_schedule)).to eq(%w(daily daily))
      end
    end

    context "when there are multi-ecosystem configs and standalone configs" do
      let(:config_file_body) do
        <<~YAML
          version: 2

          multi-ecosystem-groups:
            rails-and-rspec:
              schedule:
                interval: "daily"

          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              patterns:
                - "rails*"
                - "rspec*"
              multi-ecosystem-group: "rails-and-rspec"

            - package-ecosystem: "npm"
              directory: "/"
              patterns: ["react*"]
              multi-ecosystem-group: "rails-and-rspec"

            - package-ecosystem: "bundler"
              directory: "/"
              schedule:
                interval: "weekly"
              ignore:
                - dependency-name: "rack"

            - package-ecosystem: "bundler"
              directory: "/backend"
              schedule:
                interval: "weekly"


            - package-ecosystem: "npm"
              directory: "/frontend"
              schedule:
                interval: "weekly"
        YAML
      end

      it "updates the ignore conditions for standalone configs for the same ecosystem and directory" do
        expect { action.run }.to change(UpdateConfig, :count).by(5)

        bundler_in_root = repo.update_configs.find_by(package_manager: "bundler", directory: "/.",
                                                      multi_ecosystem_config_id: nil)

        expect(bundler_in_root.ignore_conditions.size).to eq(3)
        expect(bundler_in_root.ignore_conditions.pluck(:dependency_name)).to contain_exactly("rack", "rails*", "rspec*")

        bundler_in_backend = repo.update_configs.find_by(package_manager: "bundler", directory: "/backend",
                                                         multi_ecosystem_config_id: nil)
        expect(bundler_in_backend.ignore_conditions).to be_empty

        npm_in_frontend = repo.update_configs.find_by(package_manager: "npm_and_yarn", directory: "/frontend",
                                                      multi_ecosystem_config_id: nil)
        expect(npm_in_frontend.ignore_conditions).to be_empty
      end
    end

    context "when the schedule is changed" do
      let(:config_file_body) do
        <<~YAML
          version: 2

          multi-ecosystem-groups:
            rails-and-rspec:
              schedule:
                interval: "weekly"

          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              patterns:
                - "rails*"
                - "rspec*"
              multi-ecosystem-group: "rails-and-rspec"

            - package-ecosystem: "npm"
              directory: "/"
              patterns: ["react*"]
              multi-ecosystem-group: "rails-and-rspec"
        YAML
      end

      it "updates the existing update configs" do
        expect { action.run }.to change(UpdateConfig, :count).by(2)

        update_configs = repo.update_configs.where(multi_ecosystem_config: repo.multi_ecosystem_configs.first)
        expect(update_configs.count).to eq(2)
        expect(update_configs.pluck(:update_schedule)).to all(eq("weekly"))

        # Update the config file content to change schedule from weekly to daily
        updated_config_file = OpenStruct.new(
          path: ".github/dependabot.yml",
          content: config_file_body.gsub("weekly", "daily")
        )
        allow(fetch_config_file).to receive(:run).and_return(updated_config_file)

        expect { action.run }.not_to change(UpdateConfig, :count)
        expect(update_configs.pluck(:update_schedule)).to all(eq("daily"))
      end
    end
  end
end
