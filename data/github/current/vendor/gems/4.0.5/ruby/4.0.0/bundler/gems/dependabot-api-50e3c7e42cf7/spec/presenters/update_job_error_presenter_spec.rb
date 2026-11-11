# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateJobErrorPresenter do
  subject(:presenter) do
    described_class.new(update_job: update_job, error_hash: error_hash)
  end

  let(:error_hash) do
    { "error-type" => error_type, "error-detail" => error_detail }
  end
  let(:error_type) { "dependency_file_not_found" }
  let(:error_detail) { { "message" => "Gemfile" } }
  let(:update_job) { FactoryBot.build_stubbed(:update_job, :on_gh_actions) }

  describe "#issue_type" do
    subject { presenter.issue_type }

    it { is_expected.to eq(error_type) }
  end

  describe "#issue_detail" do
    subject { presenter.issue_detail }

    context "for a branch_not_found error" do
      let(:error_type) { "branch_not_found" }
      let(:error_detail) { { "branch-name" => "Gemfile" } }

      it { is_expected.to eq(error_detail["branch-name"]) }
    end

    context "for a directory_not_found error" do
      let(:error_type) { "directory_not_found" }
      let(:error_detail) { { "directory-name" => "/requirements" } }

      it { is_expected.to eq(error_detail["directory-name"]) }
    end

    context "for a dependency_file_not_found error" do
      let(:error_type) { "dependency_file_not_found" }
      let(:error_detail) { { "file-path" => "Gemfile" } }

      it { is_expected.to eq(error_detail["file-path"]) }
    end

    context "for a dependency_file_not_parseable error" do
      let(:error_type) { "dependency_file_not_parseable" }
      let(:error_detail) { { "file-path" => "Gemfile", "message" => "hi" } }

      it { is_expected.to eq(error_detail["file-path"]) }
    end

    context "for a dependency_file_not_evaluatable error" do
      let(:error_type) { "dependency_file_not_evaluatable" }

      it { is_expected.to eq(error_detail["message"]) }
    end

    context "for a dependency_file_content_not_changed error" do
      let(:error_type) { "dependency_file_content_not_changed" }

      it { is_expected.to eq(error_detail["message"]) }
    end

    context "for a dependency_file_not_resolvable error" do
      let(:error_type) { "dependency_file_not_resolvable" }

      it { is_expected.to eq(error_detail["message"]) }

      context "with a null byte" do
        let(:error_detail) { { "message" => "Gemfile\0stuff" } }

        it { is_expected.to eq("Gemfilestuff") }
      end

      context "with no details" do
        let(:error_detail) { nil }

        it { is_expected.to be_nil }
      end
    end

    context "for a tool_version_not_supported" do
      let(:error_type) { "tool_version_not_supported" }

      it { is_expected.to eq(nil) }
    end

    context "for a dependency_file_not_supported" do
      let(:error_type) { "dependency_file_not_supported" }

      it { is_expected.to eq(nil) }
    end

    context "for a path_dependencies_not_reachable error" do
      let(:error_type) { "path_dependencies_not_reachable" }
      let(:error_detail) { { "dependencies" => ["rails"] } }

      it { is_expected.to eq(["rails"]) }
    end

    context "for a missing_environment_variable error" do
      let(:error_type) { "missing_environment_variable" }
      let(:error_detail) { { "environment-variable" => "MY_VAR" } }

      it { is_expected.to eq("MY_VAR") }
    end

    context "for a git_dependencies_not_reachable error" do
      let(:error_type) { "git_dependencies_not_reachable" }
      let(:hostname) { Dependabot::Application.target_github_hostname(update_job.update_config.repo.account) }
      let(:error_detail) do
        { "dependency-urls" => ["https://#{hostname}/gocardless/bad.git"] }
      end

      it { is_expected.to eq("gocardless/bad") }

      context "a GitHub URL in Production (GitHub Cloud) environment", :cloud do
        let(:error_type) { "git_dependencies_not_reachable" }

        it { is_expected.to eq("gocardless/bad") }
      end

      context "and a GitHub URL in Proxima environment", :proxima do
        let(:error_type) { "git_dependencies_not_reachable" }
        let(:error_detail) do
          { "dependency-urls" => ["https://staffship-01.ghe.com/gocardless/bad.git"] }
        end

        it { is_expected.to eq("gocardless/bad") }
      end

      context "and a git URL in Production (GitHub Cloud) environment" do
        let(:error_type) { "git_dependencies_not_reachable" }
        let(:error_detail) do
          { "dependency-urls" => ["git@#{hostname}:gocardless/bad.git"] }
        end

        it { is_expected.to eq("gocardless/bad") }
      end

      context "and a git URL in Proxima environment", :proxima do
        let(:error_type) { "git_dependencies_not_reachable" }
        let(:error_detail) do
          { "dependency-urls" => ["git@staffship-01.ghe.com:gocardless/bad.git"] }
        end

        it { is_expected.to eq("gocardless/bad") }
      end

      context "and a non-GitHub URL" do
        let(:error_type) { "git_dependencies_not_reachable" }
        let(:error_detail) do
          { "dependency-urls" => ["https://bitbucket.org/gocardless/bad.git"] }
        end

        it { is_expected.to eq("https://bitbucket.org/gocardless/bad") }
      end
    end

    context "for a git_dependency_reference_not_found error" do
      let(:error_type) { "git_dependency_reference_not_found" }
      let(:error_detail) { { "dependency" => "sad_dependency" } }

      it { is_expected.to eq("sad_dependency") }
    end

    context "for a private_source_authentication_failure error" do
      let(:error_type) { "private_source_authentication_failure" }
      let(:error_detail) { { "source" => "sad.dependency.source" } }

      it { is_expected.to eq("sad.dependency.source") }
    end

    context "for a private_source_certificate_failure error" do
      let(:error_type) { "private_source_certificate_failure" }
      let(:error_detail) { { "source" => "sad.dependency.source" } }

      it { is_expected.to eq("sad.dependency.source") }
    end

    context "for a misconfigured_tooling error" do
      let(:error_type) { "misconfigured_tooling" }
      let(:error_detail) do
        {
          "tool-name" => "Yarn",
          "message" => "The yarn-path option is set to a path that does not exist in the repository",
        }
      end

      it { is_expected.to eq("The yarn-path option is set to a path that does not exist in the repository") }
    end

    context "for a go_module_path_mismatch error" do
      let(:error_type) { "go_module_path_mismatch" }
      let(:error_detail) do
        {
          "declared-path" => "staffship-01",
          "discovered-path" => "bar",
          "go-mod" => "/go.mod",
        }
      end

      it { is_expected.to include("staffship-01") }
    end

    context "for a unknown_error error" do
      let(:error_type) { "unknown_error" }

      it { is_expected.to be_nil }
    end

    context "for a file_fetcher_error error" do
      let(:error_type) { "file_fetcher_error" }

      it { is_expected.to be_nil }
    end

    context "for a update_files_error error" do
      let(:error_type) { "update_files_error" }

      it { is_expected.to be_nil }
    end

    context "for a snapshots_unavailable_graph_error error" do
      let(:error_type) { "snapshots_unavailable_graph_error" }

      it { is_expected.to be_nil }
    end

    context "for an unknown_update_graph_error error" do
      let(:error_type) { "unknown_update_graph_error" }

      it { is_expected.to be_nil }
    end

    context "for an update_graph_error error" do
      let(:error_type) { "update_graph_error" }

      it { is_expected.to be_nil }
    end

    context "for a runner_error error" do
      let(:error_type) { "runner_error" }

      it { is_expected.to be_nil }
    end

    context "for an out_of_memory error" do
      let(:error_type) { "out_of_memory" }

      it { is_expected.to be_nil }
    end

    context "for a pull_request_creation_failure error" do
      let(:error_type) { "pull_request_creation_failure" }
      let(:error_detail) { { "message" => "POST https://example.com/api/something: 422 - Something bad happened." } }

      it { is_expected.to eq("POST https://example.com/api/something: 422 - Something bad happened.") }
    end

    context "for a update_not_possible error" do
      let(:error_type) { "update_not_possible" }

      it { is_expected.to be_nil }
    end

    context "for an octokit_unauthorized error" do
      let(:error_type) { "octokit_unauthorized" }

      it { is_expected.to be_nil }
    end

    context "for a not_implemented error" do
      let(:error_type) { "not_implemented" }

      it { is_expected.to be_nil }
    end

    context "for a unexpected error" do
      let(:error_type) { "not_expected" }

      it { is_expected.to be_nil }
    end

    context "for a dependency not found error" do
      let(:error_type) { "dependency_not_found" }
      let(:error_detail) { { "source" => "npm:@gsap/business@^3.12.4" } }

      it { is_expected.to eq("npm:@gsap/business@^3.12.4") }
    end

    context "for a 'git_token_auth_error` error" do
      let(:error_type) { "git_token_auth_error" }
      let(:error_detail) { { "message" => "Missing or invalid authentication token" } }

      it { is_expected.to eq("Missing or invalid authentication token") }
    end

    context "for a tool_feature_not_supported error" do
      let(:error_type) { "tool_feature_not_supported" }
      let(:error_detail) do
        {
          "tool-name" => "pnpm",
          "tool-type" => "package_manager",
          "feature" => "updating transitive dependencies",
        }
      end

      it "returns a hash with tool_name, tool_type, and feature" do
        expect(subject).to eq(
          tool_name: "pnpm",
          tool_type: "package_manager",
          feature: "updating transitive dependencies"
        )
      end
    end
  end

  describe "#issue_title" do
    subject { presenter.issue_title }

    context "for a 'branch_not_found' error" do
      let(:error_type) { "branch_not_found" }
      let(:error_detail) do
        { "branch-name" => "Gemfile" }
      end

      let(:expected_title) do
        "Dependabot couldn't find the branch Gemfile"
      end

      it { is_expected.to eq(expected_title) }
    end

    context "for a 'directory_not_found' error" do
      let(:error_type) { "directory_not_found" }
      let(:error_detail) do
        { "directory-name" => "/requirements-3.10" }
      end

      let(:expected_title) do
        "Dependabot couldn't find the directory /requirements-3.10"
      end

      it { is_expected.to eq(expected_title) }
    end

    context "for a 'pull_request_creation_failure' error" do
      let(:error_type) { "pull_request_creation_failure" }

      let(:expected_title) do
        "Dependabot failed to create a pull request"
      end

      it { is_expected.to eq(expected_title) }
    end

    context "for a 'internal_pull_request_creation_failure' error" do
      let(:error_type) { "internal_pull_request_creation_failure" }

      let(:expected_title) do
        "Dependabot cannot track a pull request from this job"
      end

      it { is_expected.to eq(expected_title) }
    end

    context "for a 'job_repo_not_found'" do
      let(:error_type) { "job_repo_not_found" }

      it { is_expected.to eq("Dependabot couldn't access the repository") }
    end

    context "for a 'runner_error' error" do
      let(:error_type) { "runner_error" }

      let(:expected_title) do
        "Dependabot encountered an unknown error"
      end

      it { is_expected.to eq(expected_title) }
    end

    context "for a 'update_not_possible' error" do
      let(:error_type) { "update_not_possible" }

      let(:expected_title) do
        "Dependabot cannot update to the required version"
      end

      it { is_expected.to eq(expected_title) }
    end

    context "for a tool_version_not_supported error" do
      let(:error_type) { "tool_version_not_supported" }
      let(:error_detail) do
        { "tool-name" => "Python", "detected-version" => "3.6.9",
          "supported-versions" => "3.11.*, 3.10.*, 3.9.*, 3.8.*", }
      end

      it do
        expect(subject).to eq(
          "Dependabot does not support your Python version"
        )
      end
    end

    context "for a misconfigured_tooling error" do
      let(:error_type) { "misconfigured_tooling" }
      let(:error_detail) do
        {
          "tool-name" => "Yarn",
          "message" => "The yarn-path option is set to a path that does not exist in the repository",
        }
      end

      it do
        expect(subject).to eq(
          "Dependabot could not run Yarn to update your dependencies due to a configuration error"
        )
      end
    end

    context "for a dependency_file_not_supported error" do
      let(:error_type) { "dependency_file_not_supported" }
      let(:error_detail) { { "dependency-name" => "dummy-a" } }

      it do
        expect(subject).to eq(
          "Dependabot can't update vulnerable dependencies without a lockfile"
        )
      end

      context "when the package manager doesn't support lockfiles" do
        before { update_job.update_config.package_manager = "maven" }

        it do
          expect(subject).to eq(
            "Dependabot can't update vulnerable dependencies without a "\
            "pinned version"
          )
        end
      end
    end

    context "for a 'open_pull_request_limit_exceeded' error" do
      let(:error_type) { "open_pull_request_limit_exceeded" }

      let(:expected_title) do
        "Dependabot cannot open any more pull requests"
      end

      it { is_expected.to eq(expected_title) }
    end

    context "for a 'timed_out' error" do
      let(:error_type) { "timed_out" }

      let(:expected_title) do
        "Dependabot timed out during its update"
      end

      it { is_expected.to eq(expected_title) }
    end

    context "for a dependency_file_content_not_changed error" do
      let(:error_type) { "dependency_file_content_not_changed" }

      it { is_expected.to eq("Dependency file content did not change") }
    end

    context "for a 'all_versions_ignored' error" do
      let(:error_type) { "all_versions_ignored" }

      let(:expected_title) do
        "Dependabot cannot update to the required version as all versions "\
        "were ignored"
      end

      it { is_expected.to eq(expected_title) }
    end

    context "for a 'pull_request_exists_for_latest_version' error" do
      let(:error_type) { "pull_request_exists_for_latest_version" }

      let(:expected_title) do
        "Dependabot cannot update to the required version as there is already"\
        " an existing pull request for the latest version"
      end

      it { is_expected.to eq(expected_title) }
    end

    context "for a 'pull_request_exists_for_security_update' error" do
      let(:error_type) { "pull_request_exists_for_security_update" }

      let(:expected_title) do
        "Dependabot cancelled the update as there is already an "\
        "existing pull request for the fixed version"
      end

      it { is_expected.to eq(expected_title) }
    end

    context "for a 'edited_pull_request_exists' error" do
      let(:error_type) { "edited_pull_request_exists" }
      let(:error_detail) do
        {
          "updated-dependencies" => [{
            "dependency-name" => "business",
          }],
          "edited-pull-request-id": 1,
        }
      end

      let(:expected_title) do
        "Dependabot cancelled the update as there is an existing edited "\
        "pull request for business"
      end

      it { is_expected.to eq(expected_title) }
    end

    context "for a 'cancelled_update' error" do
      let(:error_type) { "cancelled_update" }

      let(:expected_title) do
        "Dependabot cancelled the update"
      end

      it { is_expected.to eq(expected_title) }
    end

    context "for a dependency_file_not_found error" do
      let(:error_type) { "dependency_file_not_found" }
      let(:error_detail) { { "file-path" => "some/package.json" } }
      let(:expected_title) do
        "Dependabot couldn't find a package.json"
      end

      it { is_expected.to eq(expected_title) }

      context "and the file-path is nil" do
        let(:error_detail) { { "file-path" => nil } }
        let(:expected_title) do
          "Dependabot couldn't find any dependency files in the directory"
        end

        it { is_expected.to eq(expected_title) }
      end
    end

    context "for a 'security_update_dependency_not_found` error" do
      let(:error_type) { "security_update_dependency_not_found" }
      let(:error_detail) { {} }

      let(:expected_title) do
        "Dependabot can't find the vulnerable dependency in the repository."
      end

      it { is_expected.to eq(expected_title) }
    end

    context "for a 'security_update_not_found` error" do
      let(:error_type) { "security_update_not_found" }
      let(:error_detail) do
        {
          "dependency-name" => "dummy-pkg-b",
          "dependency-version" => "1.2.0",
        }
      end

      let(:expected_title) do
        "Dependabot can't find a published or compatible non-vulnerable version "\
        "for dummy-pkg-b"
      end

      it { is_expected.to eq(expected_title) }
    end

    context "for a 'security_update_not_possible` error" do
      let(:error_type) { "security_update_not_possible" }
      let(:error_detail) do
        {
          "dependency-name" => "dummy-pkg-b",
          "latest-resolvable-version" => "1.2.0",
          "lowest-non-vulnerable-version" => "1.3.0",
        }
      end

      let(:expected_title) do
        "Dependabot cannot update dummy-pkg-b to a non-vulnerable version"
      end

      it { is_expected.to eq(expected_title) }
    end

    context "for a 'transitive_update_not_possible` error" do
      let(:error_type) { "transitive_update_not_possible" }
      let(:error_detail) do
        {
          "dependency-name" => "dummy-pkg-b",
          "latest-resolvable-version" => "1.2.0",
          "lowest-non-vulnerable-version" => "1.3.0",
        }
      end

      let(:expected_title) do
        "Dependabot cannot update dummy-pkg-b " \
        "because it is required by another dependency through a transitive dependency."
      end

      it { is_expected.to eq(expected_title) }
    end

    context "for a 'security_update_not_needed` error" do
      let(:error_type) { "security_update_not_needed" }
      let(:error_detail) do
        {
          "dependency-name" => "dummy-pkg-b",
        }
      end

      let(:expected_title) do
        "No security update is needed as dummy-pkg-b is no longer vulnerable"
      end

      it { is_expected.to eq(expected_title) }
    end

    {
      out_of_disk: "Dependabot ran out of disk space during its update",
      network_unsafe_http: "Dependabot encountered an unsafe HTTP network request",
      unexpected_external_code: "Dependabot refused to execute external code",
      secret_not_found: "Dependabot could not read a required secret",
      secret_not_valid: "Dependabot could not read a required secret",
      private_source_not_reachable: "Dependabot can't reach a dependency in a private package registry",
      private_source_authentication_failure: "Dependabot can't authenticate to a private package registry",
      private_source_bad_response: "Dependabot received an unexpected response from a private package registry",
      private_source_timed_out: "Dependabot timed out while waiting for a private package registry",
      private_source_certificate_failure:
        "Dependabot couldn't validate the certificate for a private package registry",
      dependency_not_found: "Dependabot could not find a dependency.",
      git_token_auth_error: "Dependabot can't reach a dependency in a GitHub package registry.",
      unresolvable_version: "Dependabot could not find a dependency version.",
    }.each do |err, expected_title|
      context "for a '#{err}' error" do
        let(:error_type) { err.to_s }

        it { is_expected.to eq(expected_title) }
      end
    end

    context "for a 'not_implemented' error" do
      let(:error_type) { "not_implemented" }

      let(:expected_title) do
        "Dependabot cannot complete this update"
      end

      it { is_expected.to eq(expected_title) }
    end

    context "for a tool_feature_not_supported error" do
      let(:error_type) { "tool_feature_not_supported" }
      let(:error_detail) do
        {
          "tool-name" => "pnpm",
          "tool-type" => "package_manager",
          "feature" => "updating transitive dependencies",
        }
      end

      it "returns the correct error title" do
        expect(subject).to eq(
          "Dependabot doesn't support the 'updating transitive dependencies' feature for pnpm package_manager"
        )
      end
    end
  end

  describe "#issue_body" do
    subject(:body) { presenter.issue_body }

    context "for a job_repo_not_found error in Production (GitHub Cloud) environment" do
      let(:update_job) { FactoryBot.create(:update_job) }
      let(:error_type) { "job_repo_not_found" }

      before do
        FactoryBot.create(:registry, :bundler, source: update_job.update_config.repo, name: "my-bundler")
        FactoryBot.create(:registry, :docker, source: update_job.update_config.repo, name: "my-docker")
        FactoryBot.create(:registry, :git, source: update_job.update_config.repo, name: "my-github", credentials: {
          url: Dependabot::Application.target_github_hostname(update_job.repo.account),
          username: "monalisa",
          password: "${{secrets.GIT_PASSWORD}}",
        }.to_json)

        update_job.update_config.update_config_registries.create!(registry_name: "my-bundler")
        update_job.update_config.update_config_registries.create!(registry_name: "my-docker")
        update_job.update_config.update_config_registries.create!(registry_name: "my-github")
      end

      specify do
        expect(body).to include(
          "In the config file, the my-github registry uses the ${{secrets.GIT_PASSWORD}} " \
          "access token, but that token doesn't have access to this repository. "\
          "Please provide an access token that has access to this repository."
        )
      end
    end

    context "for a job_repo_not_found error in GitHub Proxima environment", :proxima do
      let(:update_job) { FactoryBot.create(:update_job) }
      let(:error_type) { "job_repo_not_found" }

      before do
        FactoryBot.create(:registry, :bundler, source: update_job.update_config.repo, name: "my-bundler")
        FactoryBot.create(:registry, :docker, source: update_job.update_config.repo, name: "my-docker")
        FactoryBot.create(:registry, :git, source: update_job.update_config.repo, name: "my-github", credentials: {
          url: "staffship-01.ghe.com",
          username: "monalisa",
          password: "${{secrets.GIT_PASSWORD}}",
        }.to_json)

        update_job.update_config.update_config_registries.create!(registry_name: "my-bundler")
        update_job.update_config.update_config_registries.create!(registry_name: "my-docker")
        update_job.update_config.update_config_registries.create!(registry_name: "my-github")
      end

      specify do
        expect(body).to include(
          "In the config file, the my-github registry uses the ${{secrets.GIT_PASSWORD}} " \
          "access token, but that token doesn't have access to this repository. "\
          "Please provide an access token that has access to this repository."
        )
      end
    end

    context "for a job_repo_not_found error without a matching git source" do
      let(:update_job) { FactoryBot.create(:update_job) }
      let(:error_type) { "job_repo_not_found" }

      before do
        FactoryBot.create(:registry, :bundler, source: update_job.update_config.repo, name: "my-bundler")
        update_job.update_config.update_config_registries.create!(registry_name: "my-bundler")
      end

      specify do
        expect(body).to include(
          "Dependabot encountered a temporary problem accessing the repository. " \
          "Please [check for updates again](https://docs.github.com/en/github/managing-security-vulnerabilities/troubleshooting-dependabot-errors#triggering-a-dependabot-pull-request-manually)."
        )
      end
    end

    context "for a git_dependencies_not_reachable error" do
      let(:account) { FactoryBot.create(:account, :org) }
      let(:repo) { FactoryBot.create(:repo, account: account, private: true) }
      let(:package_manager) do
        package_managers_with_repository_access =
          PackageManagers::ALL - UpdateConfig::PACKAGE_MANAGERS_WITH_CODE_EXECUTION
        package_managers_with_repository_access.first
      end
      let(:update_config) { FactoryBot.create(:update_config, repo: repo, package_manager: package_manager) }
      let(:update_job) { FactoryBot.create(:update_job, update_config: update_config) }
      let(:error_type) { "git_dependencies_not_reachable" }
      let(:hostname) { Dependabot::Application.target_github_hostname(account) }
      let(:error_detail) do
        { "dependency-urls" => ["https://#{hostname}/hmarr/bad.git"] }
      end

      it do
        expect(body).to include("granting Dependabot access to the repository")
        expect(body).to include("checking for updates again")
        expect(body).to include("caused the update to fail: [bad](https://#{hostname}/hmarr/bad)")
      end

      context "for a GitHub Proxima environment URL", :proxima do
        let(:error_detail) do
          { "dependency-urls" => ["https://staffship-01.ghe.com/hmarr/bad.git"] }
        end

        it do
          expect(body).to include("granting Dependabot access to the repository")
          expect(body).to include("checking for updates again")
          expect(body).to include("caused the update to fail: [bad](https://staffship-01.ghe.com/hmarr/bad)")
        end
      end

      UpdateConfig::PACKAGE_MANAGERS_WITH_CODE_EXECUTION.each do |pm|
        context "for a #{pm} update job" do
          let(:package_manager) { pm }

          it do
            expect(body).to include(
              "Dependabot can't update #{pm} dependency files that reference private git repositories."
            )
          end

          it { expect(body).to include(described_class::GitDependenciesNotSupportedPresenter::GIT_REGISTRY_HELP_URL) }
        end
      end

      context "for repo belonging to personal user account" do
        let(:account) { FactoryBot.create(:account, :user) }

        it do
          expect(body).to include(
            "Personal user accounts don't support updating dependency files that reference private git repositories."
          )
        end

        it { expect(body).to include(described_class::GitDependenciesNotSupportedPresenter::GIT_REGISTRY_HELP_URL) }
      end

      context "for a public repo" do
        let(:repo) { FactoryBot.create(:repo, account: account, private: false) }

        it do
          expect(body).to include(
            "Public repositories don’t support updating dependency files that reference private git repositories."
          )
        end

        it { expect(body).to include(described_class::GitDependenciesNotSupportedPresenter::GIT_REGISTRY_HELP_URL) }
      end

      context "for dependency belonging to a different account" do
        let(:account) { FactoryBot.create(:account, :org, github_login: "dunder-mifflin") }
        let(:hostname) { Dependabot::Application.target_github_hostname(account) }
        let(:error_detail) do
          { "dependency-urls" => ["https://#{hostname}/michael-scott-paper-company/bad.git"] }
        end

        it do
          expect(body).to include(
            "The following git repository was unreachable and caused the update to fail: "\
            "[bad](https://#{hostname}/michael-scott-paper-company/bad).\n\n"\
            "Dependabot can't update dependency files that reference private git repositories owned by other accounts."
          )
        end

        it { expect(body).to include(described_class::GitDependenciesNotSupportedPresenter::GIT_REGISTRY_HELP_URL) }
      end

      context "for a non-GitHub URL" do
        let(:error_detail) do
          { "dependency-urls" => ["https://bitbucket.org/hmarr/bad.git"] }
        end

        it do
          expect(body).to include(
            "The following git repository was unreachable and caused the update to fail: "\
            "[bad](https://bitbucket.org/hmarr/bad).\n\n"\
            "Dependabot can't update dependency files that reference private git repositories hosted on external sites."
          )
        end

        it { expect(body).to include(described_class::GitDependenciesNotSupportedPresenter::GIT_REGISTRY_HELP_URL) }
      end
    end

    context "for a 'branch_not_found' error" do
      let(:error_type) { "branch_not_found" }
      let(:error_detail) { { "branch-name" => "Gemfile" } }

      it do
        expect(subject).to eq(
          "Dependabot was set up to create pull requests against the branch `Gemfile`, but couldn't find it."
        )
      end
    end

    context "for a 'directory_not_found' error" do
      let(:error_type) { "directory_not_found" }
      let(:error_detail) { { "directory-name" => "/requirements-3.10" } }

      it do
        expect(subject).to eq(
          "Dependabot was set up to run in directory `/requirements-3.10`, but couldn't find it."
        )
      end
    end

    context "for a dependency_file_not_found error" do
      let(:error_type) { "dependency_file_not_found" }
      let(:error_detail) { { "file-path" => "some/Gemfile" } }

      it do
        expect(subject).to include(
          "Dependabot requires a Gemfile to evaluate your " \
          "Ruby dependencies. It had expected to find " \
          "one at the path: `some/Gemfile`."
        )
      end

      context "without a nil file-path" do
        let(:error_detail) { { "file-path" => nil } }

        it do
          expect(subject).to include("Dependabot couldn't find any dependency files in the configured directory")
        end
      end
    end

    context "for a dependency_file_not_evaluatable error" do
      let(:error_type) { "dependency_file_not_evaluatable" }
      let(:error_detail) { { "message" => "Shit was messed up" } }

      it { is_expected.to include("\n\n```\nShit was messed up\n```") }
    end

    context "for a dependency_file_not_parseable error" do
      let(:error_type) { "dependency_file_not_parseable" }
      let(:error_detail) do
        { "message" => "Exception happened", "file-path" => "dir/manifest.txt" }
      end

      it do
        expect(subject).to include("manifest.txt found at `dir/manifest.txt`")
        expect(subject).to include("```\nException happened\n```")
      end
    end

    context "for a tool_version_not_supported error" do
      let(:error_type) { "tool_version_not_supported" }

      context "when supported-versions is present" do
        let(:error_detail) do
          { "tool-name" => "Python", "detected-version" => "3.6.9",
            "supported-versions" => "3.11.*, 3.10.*, 3.9.*, 3.8.*", }
        end

        it "returns the correct error body" do
          expect(body).to eq(
            "Dependabot detected the following Python requirement for your project: '3.6.9'." \
            "\n\nCurrently, the following Python versions are supported in " \
            'Dependabot: 3.11.\*, 3.10.\*, 3.9.\*, 3.8.\*.'
          )
        end
      end

      context "when supported-versions is nil" do
        let(:error_detail) do
          { "tool-name" => "Python", "detected-version" => "3.6.9",
            "supported-versions" => nil, }
        end

        it "returns the correct error body" do
          expect(body).to eq(
            "Dependabot detected the following Python requirement for your project: '3.6.9'."
          )
        end
      end

      context "when supported-versions is missing" do
        let(:error_detail) do
          { "tool-name" => "Python", "detected-version" => "3.6.9" }
        end

        it "returns the correct error body" do
          expect(body).to eq(
            "Dependabot detected the following Python requirement for your project: '3.6.9'."
          )
        end
      end
    end

    context "for a dependency_file_not_supported error" do
      let(:error_type) { "dependency_file_not_supported" }
      let(:error_detail) { { "dependency-name" => "dummy-a" } }

      it do
        expect(subject).to start_with(
          "The currently installed version can't be determined."
        )
      end

      context "when the package manager doesn't support lockfiles" do
        before { update_job.update_config.package_manager = "maven" }

        it do
          expect(subject).to eq(
            "The currently installed version can't be determined.\n\n"\
            "To resolve the issue pin the version to a specific release in your manifest file."
          )
        end
      end
    end

    context "for a dependency_file_content_not_changed error" do
      let(:error_type) { "dependency_file_content_not_changed" }
      let(:expected_body) do
        "Dependabot failed to update your dependencies because there "\
        "is no difference between the current and previous requirements."
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for a private_source_authentication_failure" do
      let(:error_type) { "private_source_authentication_failure" }
      let(:error_detail) { { "source" => "sad.dependency.source" } }

      it do
        expect(subject).to include(
          "private package registry was used and caused the update to fail: "\
          "sad.dependency.source"
        )
      end
    end

    context "for a git_dependency_reference_not_found error" do
      let(:error_type) { "git_dependency_reference_not_found" }
      let(:error_detail) { { "dependency" => "prius" } }

      context "for a non-Ruby update job" do
        before { update_job.update_config.package_manager = "npm_and_yarn" }

        it { is_expected.not_to include("For Ruby dependencies") }
      end

      context "for a Ruby update job" do
        before { update_job.update_config.package_manager = "bundler" }

        it { is_expected.to include("For Ruby dependencies") }
      end
    end

    context "for a path_dependencies_not_reachable error" do
      let(:error_type) { "path_dependencies_not_reachable" }
      let(:error_detail) { { "dependencies" => %w(prius whatever) } }

      it { is_expected.to include("were `prius` and `whatever`.") }
    end

    context "for a missing_environment_variable error" do
      let(:error_type) { "missing_environment_variable" }
      let(:error_detail) { { "environment-variable" => "ACF_PRO_KEY" } }

      it do
        expect(subject).to include(
          "variable was required and caused the update to fail: ACF_PRO_KEY."
        )
      end
    end

    context "for a misconfigured_tooling error" do
      let(:error_type) { "misconfigured_tooling" }
      let(:error_detail) do
        {
          "tool-name" => "Yarn",
          "message" => "The yarn-path option is set to a path that does not exist in the repository",
        }
      end

      it do
        expect(subject).to include("Please review your Yarn setup")
        expect(subject).to include("The yarn-path option is set to a path that does not exist in the repository")
      end
    end

    context "for a go_module_path_mismatch error" do
      let(:error_type) { "go_module_path_mismatch" }
      let(:error_detail) do
        {
          "declared-path" => "staffship-01",
          "discovered-path" => "bar",
          "go-mod" => "/go.mod",
        }
      end

      it do
        expect(subject).to include("`staffship-01` found in your `/go.mod`")
        expect(subject).to include("`bar` found in the dependency's `go.mod`")
      end
    end

    context "for a 'pull_request_creation_failure' error" do
      let(:error_type) { "pull_request_creation_failure" }
      let(:error_detail) { { "message" => "POST https://example.com/api/something: 422 - Something bad happened." } }

      let(:expected_body) do
        <<~BODY.chomp
          Dependabot ran into an issue when attempting to create the pull request

          Dependabot encountered the following error:

          ```
          POST https://example.com/api/something: 422 - Something bad happened.
          ```
        BODY
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for an 'internal_pull_request_creation_failure' error" do
      let(:error_type) { "internal_pull_request_creation_failure" }
      let(:github_number) { 123 }
      let(:error_detail) { { "github_number" => github_number } }

      let(:expected_body) do
        <<~BODY.squish
          During job execution, Dependabot created a pull request (#{github_number}),
          which it will not be able to track.
        BODY
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for a 'runner_error' error" do
      let(:error_type) { "runner_error" }

      let(:expected_body) do
        "Dependabot failed to update your dependencies because an unexpected error occurred. "\
        "See the logs for more details."
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for a 'update_not_possible' error" do
      let(:error_type) { "update_not_possible" }

      let(:expected_body) do
        "One or more other dependencies require a version that is incompatible with this update."
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for a 'open_pull_request_limit_exceeded' error" do
      let(:error_type) { "open_pull_request_limit_exceeded" }

      let(:expected_body) do
        "The open pull request limit has been exceeded. The current limit is: 5.\n\n"\
        "Dependabot will open new pull requests once you merge or close the "\
        "already open pull requests. You can also update this limit in the "\
        "config file."
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for a 'timed_out' error" do
      let(:error_type) { "timed_out" }

      let(:expected_body) do
        "Dependabot failed to update your dependencies because it took too long to complete."
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for a 'all_versions_ignored' error" do
      let(:error_type) { "all_versions_ignored" }

      let(:expected_body) do
        "Dependabot was configured to ignore all versions that could satisfy "\
        "this requirement."
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for a 'pull_request_exists_for_latest_version' error" do
      let(:error_type) { "pull_request_exists_for_latest_version" }
      let(:error_detail) { { "dependency-version" => "1.2.0" } }

      let(:expected_body) do
        "There is already an existing pull request for the latest version: 1.2.0"
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for a 'pull_request_exists_for_security_update' error" do
      let(:error_type) { "pull_request_exists_for_security_update" }
      let(:error_detail) do
        {
          "updated-dependencies" => [{
            "dependency-name" => "dummy-pkg-b",
            "dependency-version" => "1.2.0",
          }],
        }
      end

      let(:expected_body) do
        "There is already an existing pull request for the fixed version: `dummy-pkg-b@1.2.0`"
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for a 'pull_request_exists_for_security_update' error with a removed transitive dependency" do
      let(:error_type) { "pull_request_exists_for_security_update" }
      let(:error_detail) do
        {
          "updated-dependencies" => [
            {
              "dependency-name" => "dummy-pkg-a",
              "dependency-removed" => true,
            },
            {
              "dependency-name" => "dummy-pkg-b",
              "dependency-version" => "1.2.0",
            },
          ],
        }
      end

      let(:expected_body) do
        "There is already an existing pull request for the fixed version: `dummy-pkg-a@removed, dummy-pkg-b@1.2.0`"
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for a 'edited_pull_request_exists' error" do
      let!(:repo) { FactoryBot.create(:repo, :bump_test) }
      let!(:pull_request) { FactoryBot.create(:pull_request, repo: repo, github_number: 9991) }
      let(:error_type) { "edited_pull_request_exists" }
      let(:error_detail) do
        {
          "updated-dependencies" => [{
            "dependency-name" => "business",
          }],
          "edited-pull-request-id" => pull_request.id,
        }
      end

      let(:expected_body) do
        "There is an existing open pull request for `business` that has "\
        "been edited by someone other than Dependabot: "\
        "https://github.com/dependabot/bump-test/pull/9991\n\n"\
        "You can retry this update once the edited pull request is closed or merged."
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for a 'cancelled_update' error" do
      let(:error_type) { "cancelled_update" }

      let(:expected_body) do
        "The repository is no longer supported."
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for a 'security_update_dependency_not_found` error" do
      let(:error_type) { "security_update_dependency_not_found" }
      let(:error_detail) { {} }

      let(:expected_body) do
        "This is an indirect dependency not explicitly present in any manifest file, so Dependabot cannot update it."
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for a 'security_update_not_found` error" do
      let(:error_type) { "security_update_not_found" }
      let(:error_detail) do
        {
          "dependency-name" => "dummy-pkg-b",
          "dependency-version" => "1.2.0",
        }
      end

      let(:expected_body) do
        "The latest published and compatible version is `1.2.0`."
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for a 'transitive_update_not_possible` error" do
      let(:error_type) { "transitive_update_not_possible" }
      let(:error_detail) do
        {
          "dependency-name" => "dummy-pkg-b",
          "latest-resolvable-version" => "1.2.0",
          "lowest-non-vulnerable-version" => "1.3.0",
          "conflicting-dependencies" => [
            {
              "explanation" => "dummy-pkg-a@1.0.0 requires dummy-pkg-b@1.2.0 via a transitive dependency on " \
                      "dummy-pkg-c@1.0.0",
              "name" => "dummy-pkg-a",
              "version" => "1.0.0",
              "requirement" => "= 1.1.0",
            },
          ],
        }
      end

      let(:expected_body) do
        <<~BODY
          The latest possible version of dummy-pkg-b that can be installed is `1.2.0` because of the following conflicting dependencies:

          ```
          dummy-pkg-a@1.0.0 requires dummy-pkg-b@1.2.0 via a transitive dependency on dummy-pkg-c@1.0.0
          ```

          The earliest fixed version is `1.3.0`.
        BODY
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for a 'security_update_not_possible` error" do
      let(:error_type) { "security_update_not_possible" }
      let(:error_detail) do
        {
          "dependency-name" => "dummy-pkg-b",
          "latest-resolvable-version" => "1.2.0",
          "lowest-non-vulnerable-version" => "1.3.0",
        }
      end

      let(:expected_body) do
        "The latest possible version of dummy-pkg-b that can be installed is `1.2.0`.\n\n"\
        "The earliest fixed version is `1.3.0`."
      end

      it { is_expected.to eq(expected_body) }

      context "with conflicting dependencies" do
        let(:error_detail) do
          {
            "dependency-name" => "dummy-pkg-b",
            "latest-resolvable-version" => "1.1.0",
            "lowest-non-vulnerable-version" => "1.3.0",
            "conflicting-dependencies" => [
              {
                "explanation" => "dummy-pkg-a (1.0.0) requires dummy-pkg-b (= 1.1.0)",
                "name" => "dummy-pkg-a",
                "version" => "1.0.0",
                "requirement" => "= 1.1.0",
              },
              {
                "explanation" => "dummy-pkg-c (2.0.0) requires dummy-pkg-b (=< 1.2.0)",
                "name" => "dummy-pkg-c",
                "version" => "2.0.0",
                "requirement" => "=< 1.2.0",
              },
            ],
          }
        end

        let(:expected_body) do
          <<~BODY
            The latest possible version that can be installed is `1.1.0` because of the following conflicting dependencies:

            ```
            dummy-pkg-a (1.0.0) requires dummy-pkg-b (= 1.1.0)
            dummy-pkg-c (2.0.0) requires dummy-pkg-b (=< 1.2.0)
            ```

            The earliest fixed version is `1.3.0`.
          BODY
        end

        it { is_expected.to eq(expected_body) }
      end

      context "with malformed conflicting dependencies" do
        let(:error_detail) do
          {
            "dependency-name" => "dummy-pkg-b",
            "latest-resolvable-version" => "1.2.0",
            "lowest-non-vulnerable-version" => "1.3.0",
            "conflicting-dependencies" => "mystery string",
          }
        end

        it "sends a trace to Sentry" do
          expect(Failbot).to receive(:report!).with(an_instance_of(NoMethodError), {})

          subject
        end

        it "logs the unexpected string value" do
          expect(Dependabot::Logger).to receive(:info).with(
            msg: "unexpected value for 'conflicting-dependencies'",
            "code.namespace": "UpdateJobErrorPresenter",
            value: "mystery string",
            "gh.actions.workflow_run.id" => update_job.actions_workflow_run_id,
            "gh.repo.id": update_job.update_config.repo.github_id,
            "gh.repo.visibility": "private",
            "gh.dependabot_api.update_job.id": update_job.id,
            "gh.dependabot_api.update_job.runner_type": update_job.runner_type,
            "gh.dependabot_api.update_config.id": update_job.update_config.id,
            "gh.owner.id": update_job.update_config.repo.account.github_id,
          )

          subject
        end

        it "fails over to a simple error body" do
          expect(subject).to eq(expected_body)
        end
      end
    end

    context "for a 'security_update_not_needed` error" do
      let(:error_type) { "security_update_not_needed" }
      let(:error_detail) do
        {
          "dependency-name" => "dummy-pkg-b",
        }
      end

      let(:expected_body) do
        "Dependabot hasn't attempted to update dummy-pkg-b as it's no longer "\
        "vulnerable."
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for an 'out_of_disk' error" do
      let(:error_type) { "out_of_disk" }

      let(:expected_body) do
        "Dependabot failed to update your dependencies because there was not enough disk space available."
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for a 'network_unsafe_http' error" do
      let(:error_type) { "network_unsafe_http" }

      let(:expected_body) do
        "Dependabot failed to update your dependencies because there was an unsafe HTTP network request. "\
         "Please make sure any private registries are accessed over HTTPS."
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for an 'unexpected_external_code' error" do
      let(:error_type) { "unexpected_external_code" }

      let(:expected_body) do
        "Dependabot blocked external code required for this update. "\
        "Please set `insecure-external-code-execution: allow` in the config "\
        "if you trust all dependencies' supply chain."
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for a 'secret_not_found' error" do
      let(:error_type) { "secret_not_found" }
      let(:error_detail) { { "secret-name" => "MY_MISSING_PAT" } }

      let(:expected_body) do
        "The secret `MY_MISSING_PAT` referenced in the config file could not be read. "\
        "Please ensure the secret has been created and that this repo has access to it."
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for a 'secret_not_valid' error" do
      let(:error_type) { "secret_not_valid" }
      let(:error_detail) { { "secret-name" => "MY_INVALID_SECRET" } }

      let(:expected_body) do
        "The secret `MY_INVALID_SECRET` referenced in the config file could not be read. "\
        "Please ensure the secret has been created and that this repo has access to it."
      end

      it { is_expected.to eq(expected_body) }
    end

    %w(
      private_source_not_reachable
      private_source_authentication_failure
      private_source_bad_response
      private_source_timed_out
      private_source_certificate_failure
    ).each do |err|
      let(:error_detail) { { "source" => "rubygems.pkg.github.com" } }

      context "for a '#{err}' error" do
        let(:error_type) { err }
        let(:expected_body) do
          "The following private package registry was used and caused the update to fail: rubygems.pkg.github.com."
        end

        it { is_expected.to eq(expected_body) }
      end
    end

    context "for a 'not_implemented' error" do
      let(:error_type) { "not_implemented" }
      let(:error_detail) { { "message" => "Bundler 2 adapter does not yet implement parsed_gemfile" } }

      let(:expected_body) do
        "The job attempted to use an unimplemented method, please contact support."
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for a 'dependency_not_found` error" do
      let(:error_type) { "dependency_not_found" }
      let(:error_detail) { { "source" => "npm:@gsap/business@^3.12.4" } }

      let(:expected_body) do
        "The following dependency could not be found : npm:@gsap/business@^3.12.4"
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for a 'unresolvable_version` error" do
      let(:error_type) { "unresolvable_version" }
      let(:error_detail) { { "dependencies" => ["taiki-e/install-action@nextest"] } }

      let(:expected_body) do
        "Dependabot could not resolve semantic versions for dependencies : taiki-e/install-action@nextest"
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for a 'git_token_auth_error` error" do
      let(:error_type) { "git_token_auth_error" }
      let(:error_detail) { { "message" => "Missing or invalid authentication token" } }

      let(:expected_body) do
        "Dependabot encountered a Git authorization failure : Missing or invalid authentication token"
      end

      it { is_expected.to eq(expected_body) }
    end

    context "for a tool_feature_not_supported error" do
      let(:error_type) { "tool_feature_not_supported" }
      let(:error_detail) do
        {
          "tool-name" => "pnpm",
          "tool-type" => "package_manager",
          "feature" => "updating transitive dependencies",
        }
      end

      it "returns the correct error body" do
        expect(subject).to eq(
          "Dependabot attempted to update your dependencies but encountered an unsupported feature: " \
          "'updating transitive dependencies' for pnpm package_manager. " \
          "Currently, this feature is not supported by Dependabot.\n\n"
        )
      end
    end
  end

  context "Action service errors" do
    context "actions_service_unavailable" do
      let(:error_type) { "actions_service_unavailable" }
      let(:error_detail) { { "message" => "not used by presenter." } }

      it { expect(presenter.issue_title).to eql("Actions runners unavailable") }

      it {
        expect(presenter.issue_body).
          to eql("Dependabot was unable to update your dependencies as no Actions runners were available.")
      }

      it { expect(presenter.issue_detail).to be_nil }
    end

    %w(
      actions_service_failed
      actions_service_unprocessable
      actions_service_repository_not_found
      actions_service_unknown
    ).each do |action_error_type|
      let(:error_type) { action_error_type }
      let(:error_detail) { { "message" => "not used by presenter." } }

      it { expect(presenter.issue_title).to eql("Dependabot encountered an unknown error") }

      it {
        expect(presenter.issue_body).
          to eql("Dependabot failed to update your dependencies because an unexpected error occurred. "\
                 "See the logs for more details.")
      }

      it { expect(presenter.issue_detail).to be_nil }
    end
  end

  # rubocop:disable Layout/LineLength
  context "self-hosted Action workflow errors" do
    context "actions_workflow_image" do
      let(:error_type) { "actions_workflow_image" }
      let(:error_detail) { { "message" => "not used by presenter." } }
      let(:update_job) { FactoryBot.build_stubbed(:update_job, runner_type: UpdateJob::RUNNER_SELF_HOSTED) }
      let(:hostname) { Dependabot::Application.target_github_hostname(update_job.update_config.repo.account) }

      it { expect(presenter.issue_title).to eql("Actions encountered a problem preparing Dependabot") }

      it {
        expect(presenter.issue_body).
          to eql(
            "Dependabot was unable to update your dependencies as Actions encountered a problem retrieving Docker images. " \
            "Please make sure Docker is running on the Actions host and can connect to #{hostname}."
          )
      }

      it { expect(presenter.issue_detail).to be_nil }
    end

    context "self_hosted_runner_unavailable" do
      let(:error_type) { "self_hosted_runner_unavailable" }
      let(:error_detail) { { "message" => "error message" } }
      let(:update_job) { FactoryBot.build_stubbed(:update_job, runner_type: UpdateJob::RUNNER_SELF_HOSTED) }
      let(:hostname) { Dependabot::Application.target_github_hostname(update_job.update_config.repo.account) }

      it { expect(presenter.issue_title).to eql("Self-hosted runner unavailable") }

      it "uses the provided message from error_details if possible" do
        expect(presenter.issue_body).to eql(error_detail.fetch("message"))
      end

      it { expect(presenter.issue_detail).to be_nil }

      context "when no message is provided in the error_details" do
        let(:error_detail) { {} }

        it "uses a fallback message if none is provided in error_details" do
          expect(presenter.issue_body).
            to eql("No self-hosted runner was available to execute this job.")
        end
      end

      context "when error_detail is nil" do
        let(:error_detail) { nil }

        it "uses a fallback message if no error_detail is provided" do
          expect(presenter.issue_body).
            to eql("No self-hosted runner was available to execute this job.")
        end
      end
    end
  end

  context "GitHub-Hosted Action workflow errors" do
    context "actions_workflow_image" do
      let(:error_type) { "actions_workflow_image" }
      let(:error_detail) { { "message" => "not used by presenter." } }

      it { expect(presenter.issue_title).to eql("Actions encountered a problem preparing Dependabot") }

      it {
        expect(presenter.issue_body).
          to eql(
            "Dependabot was unable to update your dependencies as Actions encountered a problem retrieving Docker images."
          )
      }

      it { expect(presenter.issue_detail).to be_nil }
    end

    context "actions_workflow_image in GitHub Proxima environment", :proxima do
      let(:error_type) { "actions_workflow_image" }
      let(:error_detail) { { "message" => "not used by presenter." } }

      it { expect(presenter.issue_title).to eql("Actions encountered a problem preparing Dependabot") }

      it {
        expect(presenter.issue_body).
          to eql(
            "Dependabot was unable to update your dependencies as Actions encountered a problem retrieving Docker images."
          )
      }

      it { expect(presenter.issue_detail).to be_nil }
    end

    %w(
      actions_workflow_unknown
      actions_workflow_updater
    ).each do |action_error_type|
      let(:error_type) { action_error_type }
      let(:error_detail) { { "message" => "not used by presenter." } }

      it { expect(presenter.issue_title).to eql("Dependabot encountered an unknown error") }

      it {
        expect(presenter.issue_body).
          to eql("Dependabot failed to update your dependencies because an unexpected error occurred. "\
                 "See the logs for more details.")
      }

      it { expect(presenter.issue_detail).to be_nil }
    end
  end
  # rubocop:enable Layout/LineLength

  context "for a config_not_valid error" do
    let(:error_type) { "config_not_valid" }
    let(:error_detail) { { "message" => "Registry credentials invalid" } }

    it { expect(presenter.issue_title).to eql("Dependabot found a problem with its configuration") }

    it {
      expect(presenter.issue_body).
        to eql("Dependabot failed to update your dependencies because there was an error evaluating its "\
               "configuration.\n\nDependabot encountered the following error:\n\n"\
               "```\nRegistry credentials invalid\n```")
    }

    it { expect(presenter.issue_detail).to eql("Registry credentials invalid") }
  end

  context "for a resource_unavailable_to_installation error" do
    let(:error_type) { "resource_unavailable_to_installation" }
    let(:error_detail) { { "message" => "Resource unavailable to installation" } }

    it { expect(presenter.issue_title).to eql("Resource unavailable to the Dependabot installation") }

    it {
      expect(presenter.issue_body).
        to eql("The Dependabot installation does not have access to the required resources.")
    }

    it { expect(presenter.issue_detail).to be_nil }
  end
end
