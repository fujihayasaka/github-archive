# frozen_string_literal: true

require "rails_helper"

RSpec.describe ValidateConfigFile do
  subject(:validate_config_file) do
    described_class.new(repo: repo, sha: sha).run
  end

  let(:sha) { "ce587453ced02b1526dfb4cb910479d431683101" }
  let(:repo_github_id) { 88632334 }
  let(:account) { FactoryBot.create(:account, :active) }
  let(:repo) do
    FactoryBot.create(
      :repo,
      github_id: repo_github_id,
      account: account,
    )
  end

  let(:config_file) do
    OpenStruct.new(path: ".github/dependabot.yml", content: config_file_body)
  end

  let(:dummy_config_file_fetcher) do
    instance_double(FetchConfigFile, run: config_file)
  end

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:check_runs_url) do
    github_url + "repositories/#{repo.github_id}/check-runs"
  end
  let(:github_check_run) { fixture("github_responses/check_run_created.json") }

  before do
    allow(FetchConfigFile).
      to receive(:new).
      and_return(dummy_config_file_fetcher)
    allow(GitHubHelpers).to receive(:installation_access_token_for)
    stub_request(:post, check_runs_url).to_return(
      status: 201,
      body: github_check_run,
      headers: json_header,
    )
    stub_request(:patch, check_runs_url + "/4").to_return(
      status: 200,
      body: github_check_run,
      headers: json_header,
    )
  end

  context "with an invalid config file" do
    let(:config_file_body) { fixture("config_files/missing_required_key.yml") }

    it "creates a check_run" do
      validate_config_file

      expect(WebMock).to have_requested(:post, check_runs_url).with(
        body: { name: ".github/dependabot.yml", head_sha: sha }
      )
    end

    it "updates the check_run with error annotations" do
      validate_config_file

      expect(WebMock).to have_requested(:patch, check_runs_url + "/4").with(
        body: {
          conclusion: "failure",
          output: {
            summary: "Dependabot encountered the following error when parsing "\
            "your `.github/dependabot.yml`:\n\n```\nThe property '#/updates/0'"\
            " did not contain a required property of 'schedule'\n```\n\nPlease"\
            " update the config file to conform with Dependabot's "\
            "specification.",
            title: "Your .github/dependabot.yml contained invalid details",
            text: "For more info on the config file format, see [the config "\
            "file documentation](https://docs.github.com/en/github/administering-a-repository/"\
            "configuration-options-for-dependency-updates#configuration-options-for-dependabotyml)",
          },
        }
      )
    end
  end

  context "with a valid config file" do
    let(:config_file_body) { fixture("config_files/minimal.yml") }

    it "creates a check_run" do
      validate_config_file

      expect(WebMock).to have_requested(:post, check_runs_url).with(
        body: { name: ".github/dependabot.yml", head_sha: sha }
      )
    end

    it "marks the check run as succesfull" do
      validate_config_file

      expect(WebMock).to have_requested(:patch, check_runs_url + "/4").with(
        body: {
          conclusion: "success",
          output: {
            title: "Dependabot config file validation",
            summary: "All changes look good",
          },
        }
      )
    end
  end

  context "unparsable config file" do
    let(:config_file_body) { fixture("config_files/bad_alias.yml") }

    it "creates a check_run" do
      validate_config_file

      expect(WebMock).to have_requested(:post, check_runs_url).with(
        body: { name: ".github/dependabot.yml", head_sha: sha }
      )
    end

    it "updates the check_run with error annotations" do
      validate_config_file

      expect(WebMock).to have_requested(:patch, check_runs_url + "/4").with(
        body: {
          conclusion: "failure",
          output: {
            summary: "Dependabot couldn't parse the config file at "\
            "`.github/dependabot.yml`. The error raised was:\n\n```\nYAML "\
            "aliases are not supported\n```\n\nPlease ensure the config file "\
            "is a valid YAML file. An online YAML linter is available "\
            "[here](https://jsonformatter.org/yaml-validator).",
            title: "Dependabot couldn't parse the config file at "\
            ".github/dependabot.yml",
            text: "For more info on the config file format, see [the config "\
            "file documentation](https://docs.github.com/en/github/administering-a-repository/"\
            "configuration-options-for-dependency-updates#configuration-options-for-dependabotyml)",
          },
        }
      )
    end
  end

  context "with an inactive account" do
    let(:config_file_body) { fixture("config_files/missing_required_key.yml") }
    let(:account) { FactoryBot.create(:account, :inactive) }

    it "does not create a check_run" do
      validate_config_file

      expect(WebMock).not_to have_requested(:post, check_runs_url)
    end
  end

  context "grouped updates" do
    context "with only exclude patterns configured" do
      let(:config_file_body) { fixture("config_files/grouped_updates_exclude_patterns.yml") }

      it "accepts configuration" do
        validate_config_file

        expect(WebMock).to have_requested(:patch, check_runs_url + "/4").with(
          body: {
            conclusion: "success",
            output: {
              title: "Dependabot config file validation",
              summary: "All changes look good",
            },
          }
        )
      end
    end
  end

  context "with registries configuration" do
    let(:config_file_body) { fixture("config_files/npm_with_registry.yml") }

    it "accepts configuration" do
      validate_config_file

      expect(WebMock).to have_requested(:patch, check_runs_url + "/4").with(
        body: {
          conclusion: "success",
          output: {
            title: "Dependabot config file validation",
            summary: "All changes look good",
          },
        }
      )
    end

    context "with valid syntax but failing model validation" do
      let(:config_file_body) do
        config = fixture("config_files/gomod_with_gitsource.yml")
        config.gsub(/url:.*/, "url: https://github.com/kaboom")
      end

      it "creates error with validation details" do
        validate_config_file

        expect(WebMock).to have_requested(:patch, check_runs_url + "/4").with(
          body: {
            conclusion: "failure",
            output: {
              summary: "Dependabot encountered the following error when parsing your `.github/dependabot.yml`:\n\n"\
                       "```\nGit registries must specify a source in a format like `https://github.com` or "\
                       "`https://gitlab.com`. Please don't include a path.\n```\n\nPlease update the config file "\
                       "to conform with Dependabot's specification.",
              title: "Your .github/dependabot.yml contained invalid details",
              text: "For more info on the config file format, see [the config "\
              "file documentation](https://docs.github.com/en/github/administering-a-repository/"\
              "configuration-options-for-dependency-updates#configuration-options-for-dependabotyml)",
            },
          }
        )
      end
    end

    context "with unused registries" do
      let(:config_file_body) do
        config = fixture("config_files/unused_registry.yml")
        config.gsub(/url:.*/, "url: https://github.com/kaboom")
      end

      it "creates error with validation details" do
        validate_config_file

        expect(WebMock).to have_requested(:patch, check_runs_url + "/4").with(
          body: {
            conclusion: "failure",
            output: {
              summary: "Dependabot encountered the following error when parsing your `.github/dependabot.yml`:\n\n"\
                       "```\nThe property '#/registries' includes the \"npm-acme-cache\" registry "\
                       "which is not used in any of the configurations\n```\n\nPlease update the config file "\
                       "to conform with Dependabot's specification.",
              title: "Your .github/dependabot.yml contained invalid details",
              text: "For more info on the config file format, see [the config "\
              "file documentation](https://docs.github.com/en/github/administering-a-repository/"\
              "configuration-options-for-dependency-updates#configuration-options-for-dependabotyml)",
            },
          }
        )
      end
    end
  end
end
