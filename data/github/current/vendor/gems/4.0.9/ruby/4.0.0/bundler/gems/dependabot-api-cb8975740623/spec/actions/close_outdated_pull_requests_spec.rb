# frozen_string_literal: true

require "rails_helper"

RSpec.describe CloseOutdatedPullRequests do
  subject(:action) { described_class.new(pull_request: pull_request) }

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/#{repo.github_id}/" }
  let(:github_prs_body) { fixture("github_responses/pull_requests.json") }

  let(:update_config) { FactoryBot.create(:update_config, directory: "/foo") }
  let(:update_job) { FactoryBot.create(:update_job, update_config: update_config) }
  let(:repo) { update_job.update_config.repo }
  let(:pull_request) do
    FactoryBot.create(
      :pull_request,
      update_job: update_job,
      repo: repo,
      github_number: 18,
      dependencies: [
        {
          name: dependency_name,
          version: "1.5.0",
          previous_version: "1.2.0",
          directory: "/foo",
        },
      ],
      affected_directories: ["/foo"]
    )
  end
  let(:dependency_name) { "business" }

  before do
    allow(GitHubHelpers).to receive(:access_token_for)
  end

  context "when there are no previous PRs" do
    it "doesn't hit GitHub" do
      action.run
      expect(WebMock).
        not_to have_requested(:get, repo_url + "pulls?per_page=100&state=open")
    end
  end

  context "when there are previous PRs that are security updates" do
    let(:previous_update_job) do
      FactoryBot.create(
        :update_job,
        update_config: update_job.update_config,
        security_updates_only: true
      )
    end

    before do
      stub_request(:get, repo_url + "pulls?per_page=100&state=open").
        and_return(body: github_prs_body, headers: json_header)

      # create the previous PR
      FactoryBot.create(
        :pull_request,
        repo: update_job.update_config.repo,
        update_job: previous_update_job,
        created_at: 1.day.ago,
        dependencies: [
          {
            name: dependency_name,
            version: "1.4.0",
            previous_version: "1.2.0",
            directory: "/foo",
          },
        ],
        affected_directories: ["/foo"],
        github_number: 21,
        head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
        dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
      )
    end

    it "leaves the previous PR alone because security and version don't interact" do
      action.run

      expect(WebMock).not_to have_requested(:patch, repo_url + "pulls/21")
    end
  end

  context "when the config uses globs and there is a previous PR and the directory updated looks like a glob" do
    let(:dummy_pr_closer) { instance_double(ClosePullRequest, run: nil) }
    let(:previous_update_job) do
      FactoryBot.create(:update_job, update_config: update_job.update_config)
    end
    let(:pull_request) do
      FactoryBot.create(
        :pull_request,
        update_job: update_job,
        repo: repo,
        github_number: 18,
        dependencies: [
          {
            name: dependency_name,
            version: "1.5.0",
            previous_version: "1.2.0",
            directory: "/[lib]", # not a glob, directory literally named this
          },
        ],
        affected_directories: ["/[lib]"] # not a glob, directory literally named this
      )
    end

    before do
      stub_request(:get, repo_url + "pulls?per_page=100&state=open").
        and_return(body: github_prs_body, headers: json_header)

      update_job.update_config.update!(directory: nil, directories: ["/*"])

      # create the previous PR
      FactoryBot.create(
        :pull_request,
        repo: update_job.update_config.repo,
        update_job: previous_update_job,
        created_at: 1.day.ago,
        dependencies: [
          {
            name: dependency_name,
            version: "1.4.0",
            previous_version: "1.2.0",
            directory: "/[lib]", # not a glob, directory literally named this
          },
        ],
        affected_directories: ["/[lib]"], # not a glob, directory literally named this
        github_number: 21,
        head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
        dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
      )

      allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)
      stub_request(:post, repo_url + "issues/21/comments")
    end

    it "comments on the old PR and delegates to ClosePullRequest" do
      expect(dummy_pr_closer).to receive(:run)

      expect { action.run }.not_to have_enqueued_job(ClosePullRequestJob)

      expect(WebMock).
        to have_requested(:post, repo_url + "issues/21/comments").
        with(body: { body: "Superseded by #18." }.to_json)
    end
  end

  context "when there are previous PRs for the repo" do
    let(:previous_update_job) do
      FactoryBot.create(:update_job, update_config: update_job.update_config)
    end

    before do
      stub_request(:get, repo_url + "pulls?per_page=100&state=open").
        and_return(body: github_prs_body, headers: json_header)
    end

    context "for the same dependency in the same directory" do
      let(:dummy_pr_closer) { instance_double(ClosePullRequest, run: nil) }

      before do
        FactoryBot.create(
          :pull_request,
          repo: update_job.update_config.repo,
          update_job: previous_update_job,
          created_at: 1.day.ago,
          dependencies: [
            {
              name: dependency_name,
              version: "1.4.0",
              previous_version: "1.2.0",
              directory: "/foo",
            },
          ],
          affected_directories: ["/foo"],
          github_number: 21,
          head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
        )

        allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)
        stub_request(:post, repo_url + "issues/21/comments")
      end

      it "comments and closes the PR" do
        stub_request(:post, repo_url + "issues/21/comments")

        expect { action.run }.not_to have_enqueued_job(ClosePullRequestJob)

        expect(WebMock).
          to have_requested(:post, repo_url + "issues/21/comments").
          with(body: { body: "Superseded by #18." }.to_json)
      end
    end

    context "for the same dependency, but no directory is on the updated_dependencies" do
      let(:dummy_pr_closer) { instance_double(ClosePullRequest, run: nil) }

      before do
        pr = FactoryBot.create(
          :pull_request,
          repo: update_job.update_config.repo,
          update_job: previous_update_job,
          created_at: 1.day.ago,
          dependencies: [
            {
              name: dependency_name,
              version: "1.4.0",
              previous_version: "1.2.0",
              # no directory, this is intentional
            },
          ],
          github_number: 21,
          head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
        )
        # the factory will have set a default directory, let's clear it
        pr.updated_dependencies.first.update!(directory: nil)

        allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)
        stub_request(:post, repo_url + "issues/21/comments")
      end

      it "comments and closes the PR" do
        stub_request(:post, repo_url + "issues/21/comments")

        expect { action.run }.not_to have_enqueued_job(ClosePullRequestJob)

        expect(WebMock).
          to have_requested(:post, repo_url + "issues/21/comments").
          with(body: { body: "Superseded by #18." }.to_json)
      end
    end

    context "for the same dependency, but no directory on the current PR" do
      # This happens because a duplicate PR will get into CloseOutdatePullRequests
      before do
        pull_request.updated_dependencies.first.update!(directory: nil)

        FactoryBot.create(
          :pull_request,
          repo: update_job.update_config.repo,
          update_job: previous_update_job,
          created_at: 1.day.ago,
          dependencies: [
            {
              name: dependency_name,
              version: "1.4.0",
              previous_version: "1.2.0",
              directory: "/foo", # simulate this being a newer PR with directory set
            },
          ],
          github_number: 21,
          head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
        )
      end

      it "leaves the PR alone" do
        action.run

        expect(WebMock).not_to have_requested(:patch, repo_url + "pulls/21")
      end
    end

    context "for an unrelated dependency" do
      before do
        FactoryBot.create(
          :pull_request,
          repo: update_job.update_config.repo,
          update_job: previous_update_job,
          created_at: 1.day.ago,
          dependencies: [
            {
              name: "other-dep",
              version: "1.4.0",
              previous_version: "1.2.0",
              directory: "/foo",
            },
          ],
          affected_directories: ["/foo"],
          github_number: 21,
          head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
        )
      end

      it "leaves the PR alone" do
        action.run
        expect(WebMock).not_to have_requested(:patch, repo_url + "pulls/21")
      end
    end

    context "for the same dependency in a different directory" do
      before do
        FactoryBot.create(
          :pull_request,
          repo: update_job.update_config.repo,
          update_job: previous_update_job,
          created_at: 1.day.ago,
          dependencies: [
            {
              name: dependency_name,
              version: "1.4.0",
              previous_version: "1.2.0",
              directory: "/bar",
            },
          ],
          affected_directories: ["/bar"],
          github_number: 21,
          head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
        )
      end

      it "leaves the PR alone" do
        action.run
        expect(WebMock).not_to have_requested(:patch, repo_url + "pulls/21")
      end
    end

    context "for a multi-dependency PR" do
      let!(:old_pull_request) do
        FactoryBot.create(
          :pull_request,
          repo: update_job.update_config.repo,
          update_job: previous_update_job,
          created_at: 1.day.ago,
          dependencies: [
            {
              name: "other-dep",
              version: "1.4.0",
              previous_version: "1.2.0",
              directory: "/foo",
            },
            {
              name: dependency_name,
              version: "1.4.0",
              previous_version: "1.1.0",
              directory: "/foo",
            },
          ],
          affected_directories: ["/foo"],
          github_number: 21,
          head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
        )
      end

      it "leaves the PRs alone" do
        action.run
        expect(WebMock).not_to have_requested(:patch, repo_url + "pulls/21")
      end

      context "when this is a multi-dependency PR" do
        let(:pull_request) do
          FactoryBot.create(
            :pull_request,
            update_job: update_job,
            repo: repo,
            github_number: 18,
            dependencies: [
              {
                name: dependency_name,
                version: "1.5.0",
                previous_version: "1.1.0",
                directory: "/foo",
              },
              {
                name: "other-dep",
                version: "1.4.0",
                previous_version: "1.2.0",
                directory: "/foo",
              },
            ],
            affected_directories: ["/foo"]
          )
        end

        let(:dummy_pr_closer) { instance_double(ClosePullRequest, run: nil) }

        before do
          allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)
          stub_request(:post, repo_url + "issues/21/comments")
        end

        it "comments on the old PR and delegates to ClosePullRequest" do
          expect(dummy_pr_closer).to receive(:run)

          expect { action.run }.not_to have_enqueued_job(ClosePullRequestJob)

          expect(WebMock).
            to have_requested(:post, repo_url + "issues/21/comments").
            with(body: { body: "Superseded by #18." }.to_json)
        end

        context "when ClosePullRequest raises a validation error" do
          before do
            allow(dummy_pr_closer).
              to receive(:run).and_raise(ClosePullRequest::GitHubCloseBug)
          end

          it "comments on the old PR and delegates to ClosePullRequest" do
            expect { action.run }.
              to have_enqueued_job(ClosePullRequestJob).
              with(pull_request: old_pull_request, comment_on_pr: false)
            expect(WebMock).
              to have_requested(:post, repo_url + "issues/21/comments").
              with(body: { body: "Superseded by #18." }.to_json)
          end
        end
      end
    end

    context "when grouped updates creates a multi-dependency PR" do
      before do
        allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)
        stub_request(:post, repo_url + "issues/21/comments")
      end

      let(:pull_request) do
        FactoryBot.create(
          :pull_request,
          update_job: update_job,
          repo: repo,
          github_number: 18,
          multiple_dependencies: true,
          dependencies: [
            {
              name: dependency_name,
              version: "1.5.0",
              previous_version: "1.1.0",
              directory: "/foo",
            },
            {
              name: "other-dep",
              version: "1.4.0",
              previous_version: "1.2.0",
              directory: "/foo",
            },
          ],
          affected_directories: ["/foo"]
        )
      end

      context "and there is an existing single PR for the same dependency and version" do
        let(:old_pull_request) do
          FactoryBot.create(
            :pull_request,
            repo: update_job.update_config.repo,
            update_job: previous_update_job,
            created_at: 1.day.ago,
            dependencies: [
              {
                name: dependency_name,
                version: "1.4.0",
                previous_version: "1.2.0",
                directory: "/foo",
              },
            ],
            affected_directories: ["/foo"],
            github_number: 21,
            head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
            dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          )
        end

        let(:dummy_pr_closer) { instance_double(ClosePullRequest, run: nil) }

        before do
          allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)
          stub_request(:post, repo_url + "issues/#{old_pull_request.github_number}/comments")
        end

        it "comments on the old PR and delegates to ClosePullRequest" do
          expect(dummy_pr_closer).to receive(:run)

          action.run

          expect(WebMock).
            to have_requested(:post, repo_url + "issues/21/comments").
            with(body: { body: "Superseded by #18." }.to_json)
        end
      end

      context "and there is an existing multi-dependency PR that is a subset of the new PR" do
        let(:old_pull_request) do
          FactoryBot.create(
            :pull_request,
            repo: update_job.update_config.repo,
            update_job: previous_update_job,
            created_at: 1.day.ago,
            multiple_dependencies: true,
            dependencies: [
              {
                name: dependency_name,
                version: "1.4.0",
                previous_version: "1.2.0",
                directory: "/foo",
              },
            ],
            affected_directories: ["/foo"],
            github_number: 21,
            head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
            dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          )
        end

        let(:dummy_pr_closer) { instance_double(ClosePullRequest, run: nil) }

        before do
          allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)
          stub_request(:post, repo_url + "issues/#{old_pull_request.github_number}/comments")
        end

        it "comments on the old PR and delegates to ClosePullRequest" do
          expect(dummy_pr_closer).to receive(:run)

          action.run

          expect(WebMock).
            to have_requested(:post, repo_url + "issues/21/comments").
            with(body: { body: "Superseded by #18." }.to_json)
        end
      end

      context "and there is an existing multi-dependency PR that is not a superset of the new PR" do
        let(:dummy_pr_closer) { instance_double(ClosePullRequest, run: nil) }

        before do
          allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)

          FactoryBot.create(
            :pull_request,
            repo: update_job.update_config.repo,
            update_job: previous_update_job,
            created_at: 1.day.ago,
            multiple_dependencies: true,
            dependencies: [
              {
                name: dependency_name,
                version: "1.4.0",
                previous_version: "1.2.0",
                directory: "/foo",
              },
              {
                name: "hello-world",
                version: "1.4.0",
                previous_version: "1.2.0",
                directory: "/foo",
              },
            ],
            affected_directories: ["/foo"],
            github_number: 21,
            head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
            dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          )
        end

        it "leaves the PRs alone" do
          expect(dummy_pr_closer).not_to receive(:run)

          action.run
        end
      end
    end

    context "when a multi-directory grouped security updates creates a multi-dependency PR" do
      let(:previous_update_config) do
        FactoryBot.create(:update_config, repo: repo, directory: "/lib")
      end
      let(:previous_security_update_job) do
        FactoryBot.create(
          :update_job,
          update_config: previous_update_config,
          security_updates_only: true
        )
      end
      let(:multidirectory_update_config) do
        FactoryBot.create(:update_config, :grouped_update, repo: repo, directories: ["/app", "/lib"], directory: nil)
      end
      let(:multidirectory_security_update_job) do
        FactoryBot.create(
          :update_job,
          update_config: multidirectory_update_config,
          security_updates_only: true
        )
      end

      let(:dummy_pr_closer) { instance_double(ClosePullRequest, run: nil) }

      context "and there is an existing multidirectory PR for the same dependency and version" do
        before do
          allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)
          allow(Dependabot::Logger).to receive(:info)
          stub_request(:post, repo_url + "issues/21/comments")
        end

        let(:multidirectory_pull_request) do
          FactoryBot.create(
            :pull_request,
            update_job: multidirectory_security_update_job,
            update_config: multidirectory_update_config,
            repo: multidirectory_update_config.repo,
            github_number: 17,
            multiple_dependencies: true,
            created_at: 1.day.ago,
            grouped_update: true,
            dependencies: [
              {
                name: dependency_name,
                version: "1.5.0",
                previous_version: "1.1.0",
                directory: "/lib",
              },
              {
                name: "other-dep",
                version: "1.4.0",
                previous_version: "1.2.0",
                directory: "/app",
              },
            ],
            affected_directories: ["/lib", "/app"]
          )
        end

        let(:pull_request) do
          FactoryBot.create(
            :pull_request,
            repo: previous_update_config.repo,
            update_job: previous_security_update_job,
            update_config: previous_update_config,
            dependencies: [
              {
                name: dependency_name,
                version: "1.4.0",
                previous_version: "1.2.0",
                directory: "/lib",
              },
            ],
            affected_directories: ["/lib"],
            github_number: 21,
            head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
            dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          )
        end

        it "leaves the PRs alone" do
          expect(dummy_pr_closer).not_to receive(:run)
          expect(Dependabot::Logger).not_to have_received(:info)

          action.run
        end
      end

      context "and a mutldirectory security update is opened that has overlapping directories" do
        let(:unrelated_pull_request) do
          FactoryBot.create(
            :pull_request,
            repo: previous_update_config.repo,
            update_job: previous_security_update_job,
            update_config: previous_update_config,
            created_at: 1.day.ago,
            dependencies: [
              {
                name: "unrelated-dep",
                version: "1.4.0",
                previous_version: "1.2.0",
                directory: "/lib",
              },
            ],
            affected_directories: ["/lib"],
            github_number: 19,
            head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
            dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          )
        end

        let(:pull_request) do
          FactoryBot.create(
            :pull_request,
            repo: multidirectory_update_config.repo,
            update_job: multidirectory_security_update_job,
            update_config: multidirectory_update_config,
            github_number: 25,
            multiple_dependencies: true,
            grouped_update: true,
            dependencies: [
              {
                name: dependency_name,
                version: "1.5.0",
                previous_version: "1.1.0",
                directory: "/lib",
              },
              {
                name: "other-dep",
                version: "1.4.0",
                previous_version: "1.2.0",
                directory: "/app",
              },
            ],
            affected_directories: ["/lib", "/app"]
          )
        end

        before do
          allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)
        end

        context "and there is an existing single PR for the same dependency and version" do
          let(:old_pull_request) do
            FactoryBot.create(
              :pull_request,
              repo: previous_update_config.repo,
              update_job: previous_security_update_job,
              update_config: previous_update_config,
              created_at: 1.day.ago,
              dependencies: [
                {
                  name: dependency_name,
                  version: "1.4.0",
                  previous_version: "1.2.0",
                  directory: "/lib",
                },
              ],
              affected_directories: ["/lib"],
              github_number: 21,
              head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
              dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
            )
          end

          before do
            allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)
            allow(Dependabot::Logger).to receive(:info)
            stub_request(:post, repo_url + "issues/#{old_pull_request.github_number}/comments")
            stub_request(:get, repo_url + "pulls?per_page=100&state=open").
              and_return(body: github_prs_body, headers: json_header)
          end

          it "comments on the old PR and delegates to ClosePullRequest" do
            expect(dummy_pr_closer).to receive(:run).once

            action.run

            expect(WebMock).
              to have_requested(:get, repo_url + "pulls?per_page=100&state=open")
            expect(WebMock).
              to have_requested(:post, repo_url + "issues/21/comments").
              with(body: { body: "Superseded by #25." }.to_json)
            expect(WebMock).
              not_to have_requested(:post, repo_url + "issues/19/comments")
          end
        end

        context "and there are existing single PRs for the same dependencies and versions" do
          let(:old_pull_request) do
            FactoryBot.create(
              :pull_request,
              repo: previous_update_config.repo,
              update_job: previous_security_update_job,
              update_config: previous_update_config,
              created_at: 1.day.ago,
              dependencies: [
                {
                  name: dependency_name,
                  version: "1.4.0",
                  previous_version: "1.2.0",
                  directory: "/lib",
                },
              ],
              affected_directories: ["/lib"],
              github_number: 21,
              head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
              dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
            )
          end

          let(:old_pull_request2) do
            FactoryBot.create(
              :pull_request,
              repo: previous_update_config.repo,
              update_job: previous_security_update_job,
              update_config: previous_update_config,
              created_at: 1.day.ago,
              dependencies: [
                {
                  name: "other-dep",
                  version: "1.5.0",
                  previous_version: "1.2.0",
                  directory: "/app",
                },
              ],
              affected_directories: ["/app"],
              github_number: 22,
              head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
              dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
            )
          end

          before do
            allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)
            stub_request(:post, repo_url + "issues/#{old_pull_request.github_number}/comments")
            stub_request(:post, repo_url + "issues/#{old_pull_request2.github_number}/comments")
            stub_request(:get, repo_url + "pulls?per_page=100&state=open").
              and_return(body: github_prs_body, headers: json_header)
          end

          it "comments on the old PR and delegates to ClosePullRequest" do
            expect(dummy_pr_closer).to receive(:run).twice

            action.run

            expect(WebMock).
              to have_requested(:get, repo_url + "pulls?per_page=100&state=open")
            expect(WebMock).
              to have_requested(:post, repo_url + "issues/21/comments").
              with(body: { body: "Superseded by #25." }.to_json)
            expect(WebMock).
              to have_requested(:post, repo_url + "issues/22/comments").
              with(body: { body: "Superseded by #25." }.to_json)
          end
        end
      end
    end

    context "when grouped security updates creates a multi-dependency PR" do
      let(:previous_security_update_job) do
        FactoryBot.create(
          :update_job,
          update_config: update_job.update_config,
          security_updates_only: true
        )
      end
      let(:pull_request) do
        FactoryBot.create(
          :pull_request,
          update_job: previous_security_update_job,
          repo: repo,
          github_number: 18,
          multiple_dependencies: true,
          dependencies: [
            {
              name: dependency_name,
              version: "1.5.0",
              previous_version: "1.1.0",
              directory: "/foo",
            },
            {
              name: "other-dep",
              version: "1.4.0",
              previous_version: "1.2.0",
              directory: "/foo",
            },
          ],
          affected_directories: ["/foo"]
        )
      end

      before do
        allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)
        stub_request(:post, repo_url + "issues/21/comments")
      end

      context "and there is an existing single PR for the same dependency and version" do
        let(:old_pull_request) do
          FactoryBot.create(
            :pull_request,
            repo: update_job.update_config.repo,
            update_job: previous_security_update_job,
            created_at: 1.day.ago,
            dependencies: [
              {
                name: dependency_name,
                version: "1.4.0",
                previous_version: "1.2.0",
                directory: "/foo",
              },
            ],
            affected_directories: ["/foo"],
            github_number: 21,
            head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
            dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          )
        end

        let(:dummy_pr_closer) { instance_double(ClosePullRequest, run: nil) }

        before do
          allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)
          stub_request(:post, repo_url + "issues/#{old_pull_request.github_number}/comments")
        end

        it "comments on the old PR and delegates to ClosePullRequest" do
          expect(dummy_pr_closer).to receive(:run)

          action.run

          expect(WebMock).
            to have_requested(:post, repo_url + "issues/21/comments").
            with(body: { body: "Superseded by #18." }.to_json)
        end
      end

      context "and there is an existing multi-dependency PR that is a subset of the new PR" do
        let(:old_pull_request) do
          FactoryBot.create(
            :pull_request,
            repo: update_job.update_config.repo,
            update_job: previous_security_update_job,
            created_at: 1.day.ago,
            multiple_dependencies: true,
            dependencies: [
              {
                name: dependency_name,
                version: "1.4.0",
                previous_version: "1.2.0",
                directory: "/foo",
              },
            ],
            affected_directories: ["/foo"],
            github_number: 21,
            head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
            dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          )
        end

        let(:dummy_pr_closer) { instance_double(ClosePullRequest, run: nil) }

        before do
          allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)
          stub_request(:post, repo_url + "issues/#{old_pull_request.github_number}/comments")
        end

        it "comments on the old PR and delegates to ClosePullRequest" do
          expect(dummy_pr_closer).to receive(:run)

          action.run

          expect(WebMock).
            to have_requested(:post, repo_url + "issues/21/comments").
            with(body: { body: "Superseded by #18." }.to_json)
        end
      end

      context "and there is an existing multi-dependency PR that is not a superset of the new PR" do
        let(:dummy_pr_closer) { instance_double(ClosePullRequest, run: nil) }

        before do
          allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)

          FactoryBot.create(
            :pull_request,
            repo: update_job.update_config.repo,
            update_job: previous_security_update_job,
            created_at: 1.day.ago,
            multiple_dependencies: true,
            dependencies: [
              {
                name: dependency_name,
                version: "1.4.0",
                previous_version: "1.2.0",
                directory: "/foo",
              },
              {
                name: "hello-world",
                version: "1.4.0",
                previous_version: "1.2.0",
                directory: "/foo",
              },
            ],
            affected_directories: ["/foo"],
            github_number: 21,
            head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
            dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          )
        end

        it "leaves the PRs alone" do
          expect(dummy_pr_closer).not_to receive(:run)

          action.run
        end
      end
    end

    context "for the same dependency" do
      context "that haven't been edited manually" do
        let!(:old_pull_request) do
          FactoryBot.create(
            :pull_request,
            repo: update_job.update_config.repo,
            update_job: previous_update_job,
            created_at: 1.day.ago,
            dependencies: [
              {
                name: "business",
                version: "1.4.0",
                previous_version: "1.2.0",
                directory: "/foo",
              },
            ],
            affected_directories: ["/foo"],
            github_number: 21,
            head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
            dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          )
        end
        let(:dummy_pr_closer) { instance_double(ClosePullRequest, run: nil) }

        before do
          allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)
          stub_request(:post, repo_url + "issues/21/comments")
        end

        it "comments on the old PR and delegates to ClosePullRequest" do
          expect(dummy_pr_closer).to receive(:run)

          action.run

          expect(WebMock).
            to have_requested(:post, repo_url + "issues/21/comments").
            with(body: { body: "Superseded by #18." }.to_json)
        end

        context "but the old PR is locked" do
          let(:locked) { fixture("github_responses/forbidden_locked.json") }

          before do
            stub_request(:post, repo_url + "issues/21/comments").
              to_return(status: 403, body: locked, headers: json_header)
          end

          it "delegates to ClosePullRequest, and doesn't raise" do
            expect(dummy_pr_closer).to receive(:run)

            expect { action.run }.not_to raise_error

            expect(WebMock).
              to have_requested(:post, repo_url + "issues/21/comments").
              with(body: { body: "Superseded by #18." }.to_json)
          end
        end

        context "that included an assignee" do
          let(:github_prs_body) do
            fixture("github_responses/pull_requests.json").
              gsub('"assignees": [],', '"assignees": [{"login": "david"}],')
          end
          let(:github_pr_body) do
            fixture("github_responses/pull_request_dirty.json")
          end

          it "sets the assignee on the new PR" do
            stub_request(:post, repo_url + "issues/18/assignees").
              to_return(status: 201, body: github_pr_body, headers: json_header)

            action.run

            expect(WebMock).
              to have_requested(:post, repo_url + "issues/18/assignees").
              with(body: { assignees: ["david"] }.to_json)
          end
        end

        context "but are the PR themselves" do
          let(:pull_request) { old_pull_request }

          it "leaves the PRs alone" do
            expect(dummy_pr_closer).not_to receive(:run)
            action.run
          end
        end

        context "but have an uncheckable version" do
          let!(:old_pull_request) do
            FactoryBot.create(
              :pull_request,
              repo: update_job.update_config.repo,
              update_job: previous_update_job,
              created_at: 1.day.ago,
              dependencies: [
                {
                  name: "business",
                  version: "< 1.5.0",
                  previous_version: "1.2.0",
                  directory: "/foo",
                },
              ],
              affected_directories: ["/foo"],
              github_number: 21,
              head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
              dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
            )
          end

          it "closes the PR" do
            expect(dummy_pr_closer).to receive(:run)

            action.run

            expect(WebMock).
              to have_requested(:post, repo_url + "issues/21/comments").
              with(body: { body: "Superseded by #18." }.to_json)
          end

          context "but are the PR themselves" do
            let(:pull_request) { old_pull_request }

            it "leaves the PRs alone" do
              expect(dummy_pr_closer).not_to receive(:run)
              action.run
            end
          end
        end
      end

      context "that have been edited manually" do
        let!(:old_pr) do
          FactoryBot.create(
            :pull_request,
            repo: update_job.update_config.repo,
            update_job: previous_update_job,
            created_at: 1.day.ago,
            dependencies: [
              {
                name: "business",
                version: "1.4.0",
                previous_version: "1.2.0",
                directory: "/foo",
              },
            ],
            affected_directories: ["/foo"],
            github_number: 21,
            dependabot_commit_sha: "new-sha",
            head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          )
        end

        before do
          stub_request(:get, repo_url + "pulls/21/commits").
            to_return(status: 200, body: fixture("github_responses/commits_edited.json"), headers: json_header)
        end

        it "leaves the PRs alone" do
          action.run
          expect(WebMock).not_to have_requested(:patch, repo_url + "pulls/21")
        end

        context "and requested a recreate" do
          before do
            old_pr.transition_to!(:updating, overwrite_edits: true)
            old_pr.transition_to!(:up_to_date)
          end

          let(:dummy_pr_closer) { instance_double(ClosePullRequest, run: nil) }

          before do
            allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)
            stub_request(:post, repo_url + "issues/21/comments")
          end

          it "closes the PR" do
            expect(dummy_pr_closer).to receive(:run)

            action.run

            expect(WebMock).
              to have_requested(:post, repo_url + "issues/21/comments").
              with(body: { body: "Superseded by #18." }.to_json)
          end
        end
      end

      context "that have been edited manually with dependabot skipped commits" do
        let(:dummy_pr_closer) { instance_double(ClosePullRequest, run: nil) }
        let(:commits_body) { fixture("github_responses/commits_edited_skipped.json") }

        before do
          FactoryBot.create(
            :pull_request,
            repo: update_job.update_config.repo,
            update_job: previous_update_job,
            created_at: 1.day.ago,
            dependencies: [
              {
                name: "business",
                version: "1.4.0",
                previous_version: "1.2.0",
                directory: "/foo",
              },
            ],
            affected_directories: ["/foo"],
            github_number: 21,
            dependabot_commit_sha: "new-sha",
            head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          )

          allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)
          stub_request(:post, repo_url + "issues/21/comments")
          stub_request(:get, repo_url + "pulls/21/commits").
            to_return(status: 200, body: commits_body, headers: json_header)
        end

        it "closes the PR" do
          expect(dummy_pr_closer).to receive(:run)

          action.run

          expect(WebMock).
            to have_requested(:post, repo_url + "issues/21/comments").
            with(body: { body: "Superseded by #18." }.to_json)
        end
      end

      context "that belong to a different update config" do
        let(:other_update_config) do
          FactoryBot.create(
            :update_config, :active,
            repo: repo,
            target_branch: "different",
          )
        end
        let(:other_update_job) do
          FactoryBot.create(
            :update_job,
            update_config: other_update_config,
          )
        end

        before do
          FactoryBot.create(
            :pull_request,
            repo: other_update_config.repo,
            update_config: other_update_config,
            update_job: other_update_job,
            created_at: 1.day.ago,
            dependencies: [
              {
                name: "business",
                version: "1.4.0",
                previous_version: "1.2.0",
                directory: "/foo",
              },
            ],
            affected_directories: ["/foo"],
            github_number: 21,
            head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
            dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          )
        end

        it "leaves the PRs alone" do
          action.run
          expect(WebMock).not_to have_requested(:patch, repo_url + "pulls/21")
        end
      end
    end

    context "for a PR that removes a transitive dependency" do
      let(:old_pull_request) do
        FactoryBot.create(
          :pull_request,
          repo: update_job.update_config.repo,
          update_job: previous_update_job,
          created_at: 1.day.ago,
          dependencies: [
            {
              name: dependency_name,
              version: "1.4.0",
              previous_version: "1.2.0",
              directory: "/foo",
            },
            {
              name: "parent_dep",
              version: "1.4.0",
              previous_version: "1.1.0",
              directory: "/foo",
            },
          ],
          affected_directories: ["/foo"],
          github_number: 21,
          head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
        )
      end

      let(:pull_request) do
        FactoryBot.create(
          :pull_request,
          update_job: update_job,
          repo: repo,
          github_number: 18,
          dependencies: [
            {
              name: dependency_name,
              previous_version: "1.2.0",
              removed: true,
              directory: "/foo",
            },
            {
              name: "parent_dep",
              version: "1.6.0",
              previous_version: "1.4.0",
              directory: "/foo",
            },
          ],
          affected_directories: ["/foo"],
        )
      end

      let(:dummy_pr_closer) { instance_double(ClosePullRequest, run: nil) }

      before do
        allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)
        stub_request(:post, repo_url + "issues/#{old_pull_request.github_number}/comments")
      end

      it "comments on the old PR and delegates to ClosePullRequest" do
        expect(dummy_pr_closer).to receive(:run)

        expect { action.run }.not_to have_enqueued_job(ClosePullRequestJob)

        expect(WebMock).
          to have_requested(:post, repo_url + "issues/21/comments").
          with(body: { body: "Superseded by #18." }.to_json)
      end

      context "and the previous PR also has a removed dependency" do
        let(:old_pull_request) do
          FactoryBot.create(
            :pull_request,
            repo: update_job.update_config.repo,
            update_job: previous_update_job,
            created_at: 1.day.ago,
            dependencies: [
              {
                name: dependency_name,
                previous_version: "1.2.0",
                removed: true,
                directory: "/foo",
              },
              {
                name: "parent_dep",
                version: "1.4.0",
                previous_version: "1.1.0",
                directory: "/foo",
              },
            ],
            affected_directories: ["/foo"],
            github_number: 21,
            head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
            dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          )
        end

        it "comments on the old PR and delegates to ClosePullRequest" do
          expect(dummy_pr_closer).to receive(:run)

          expect { action.run }.not_to have_enqueued_job(ClosePullRequestJob)

          expect(WebMock).
            to have_requested(:post, repo_url + "issues/21/comments").
            with(body: { body: "Superseded by #18." }.to_json)
        end
      end
    end

    context "when a multi-ecosystem group PR is created" do
      let(:multi_ecosystem_config) { FactoryBot.create(:multi_ecosystem_config) }
      let(:bundler_update_config) do
        FactoryBot.create(:update_config, repo: repo, package_manager: "bundler",
                                          multi_ecosystem_config: multi_ecosystem_config)
      end
      let(:npm_update_config) do
        FactoryBot.create(:update_config, repo: repo, package_manager: "npm_and_yarn",
                                          multi_ecosystem_config: multi_ecosystem_config)
      end
      let(:multi_ecosystem_update_job) do
        FactoryBot.create(:update_job, update_config: bundler_update_config)
      end
      let(:pull_request) do
        FactoryBot.create(
          :pull_request,
          update_job: multi_ecosystem_update_job,
          update_config: bundler_update_config,
          repo: repo,
          github_number: 18,
          grouped_update: true,
          dependencies: [
            {
              name: "rails",
              version: "7.1.0",
              previous_version: "7.0.0",
              directory: "/",
            },
            {
              name: "lodash",
              version: "4.18.0",
              previous_version: "4.17.0",
              directory: "/",
            },
          ],
          affected_directories: ["/"]
        )
      end

      let(:dummy_pr_closer) { instance_double(ClosePullRequest, run: nil) }

      before do
        # ensure both update_configs exist
        bundler_update_config
        npm_update_config

        allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)
        stub_request(:get, repo_url + "pulls?per_page=100&state=open").
          and_return(body: github_prs_body, headers: json_header)
      end

      context "and there is an existing single-ecosystem PR for a bundler dependency" do
        before do
          previous_bundler_job = FactoryBot.create(:update_job, update_config: bundler_update_config)
          FactoryBot.create(
            :pull_request,
            repo: repo,
            update_job: previous_bundler_job,
            update_config: bundler_update_config,
            created_at: 1.day.ago,
            dependencies: [
              {
                name: "rails",
                version: "7.0.5",
                previous_version: "7.0.0",
                directory: "/",
              },
            ],
            affected_directories: ["/"],
            github_number: 21,
            head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
            dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          )

          stub_request(:post, repo_url + "issues/21/comments")
        end

        it "supersedes the bundler PR" do
          expect(dummy_pr_closer).to receive(:run)

          action.run

          expect(WebMock).
            to have_requested(:post, repo_url + "issues/21/comments").
            with(body: { body: "Superseded by #18." }.to_json)
        end
      end

      context "and there is an existing single-ecosystem PR for an npm dependency" do
        before do
          previous_npm_job = FactoryBot.create(:update_job, update_config: npm_update_config)
          FactoryBot.create(
            :pull_request,
            repo: repo,
            update_job: previous_npm_job,
            update_config: npm_update_config,
            created_at: 1.day.ago,
            dependencies: [
              {
                name: "lodash",
                version: "4.17.5",
                previous_version: "4.17.0",
                directory: "/",
              },
            ],
            affected_directories: ["/"],
            github_number: 21,
            head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
            dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          )

          stub_request(:post, repo_url + "issues/21/comments")
        end

        it "supersedes the npm PR" do
          expect(dummy_pr_closer).to receive(:run)

          action.run

          expect(WebMock).
            to have_requested(:post, repo_url + "issues/21/comments").
            with(body: { body: "Superseded by #18." }.to_json)
        end
      end

      context "and there are existing PRs across both ecosystems" do
        before do
          previous_bundler_job = FactoryBot.create(:update_job, update_config: bundler_update_config)
          FactoryBot.create(
            :pull_request,
            repo: repo,
            update_job: previous_bundler_job,
            update_config: bundler_update_config,
            created_at: 1.day.ago,
            dependencies: [
              {
                name: "rails",
                version: "7.0.5",
                previous_version: "7.0.0",
                directory: "/",
              },
            ],
            affected_directories: ["/"],
            github_number: 21,
            head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
            dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          )

          previous_npm_job = FactoryBot.create(:update_job, update_config: npm_update_config)
          FactoryBot.create(
            :pull_request,
            repo: repo,
            update_job: previous_npm_job,
            update_config: npm_update_config,
            created_at: 1.day.ago,
            dependencies: [
              {
                name: "lodash",
                version: "4.17.5",
                previous_version: "4.17.0",
                directory: "/",
              },
            ],
            affected_directories: ["/"],
            github_number: 22,
            head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
            dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          )

          stub_request(:post, repo_url + "issues/21/comments")
          stub_request(:post, repo_url + "issues/22/comments")
        end

        it "supersedes PRs from both ecosystems" do
          expect(dummy_pr_closer).to receive(:run).twice

          action.run

          expect(WebMock).
            to have_requested(:post, repo_url + "issues/21/comments").
            with(body: { body: "Superseded by #18." }.to_json)
          expect(WebMock).
            to have_requested(:post, repo_url + "issues/22/comments").
            with(body: { body: "Superseded by #18." }.to_json)
        end
      end

      context "and there is a PR for a dependency not in the group" do
        before do
          previous_npm_job = FactoryBot.create(:update_job, update_config: npm_update_config)
          FactoryBot.create(
            :pull_request,
            repo: repo,
            update_job: previous_npm_job,
            update_config: npm_update_config,
            created_at: 1.day.ago,
            dependencies: [
              {
                name: "react",
                version: "18.2.0",
                previous_version: "18.1.0",
                directory: "/",
              },
            ],
            affected_directories: ["/"],
            github_number: 21,
            head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
            dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          )
        end

        it "does not supersede the unrelated PR" do
          expect(dummy_pr_closer).not_to receive(:run)

          action.run
        end
      end

      context "and there is a PR for a completely unrelated ecosystem" do
        let(:pip_update_config) do
          FactoryBot.create(:update_config, repo: repo, package_manager: "pip")
        end

        before do
          previous_pip_job = FactoryBot.create(:update_job, update_config: pip_update_config)
          FactoryBot.create(
            :pull_request,
            repo: repo,
            update_job: previous_pip_job,
            update_config: pip_update_config,
            created_at: 1.day.ago,
            dependencies: [
              {
                name: "requests",
                version: "2.29.0",
                previous_version: "2.28.0",
                directory: "/",
              },
            ],
            affected_directories: ["/"],
            github_number: 21,
            head_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
            dependabot_commit_sha: "8532d1410c9f02d76f96d6ed75a6f5e8b2017198",
          )
        end

        it "does not supersede the PR from an unrelated ecosystem" do
          expect(dummy_pr_closer).not_to receive(:run)

          action.run
        end
      end
    end
  end
end
