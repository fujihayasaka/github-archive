# frozen_string_literal: true

require "rails_helper"

RSpec.describe HandleWebhook::IssueComment::HandleIgnoreRequest do
  subject(:action) do
    described_class.new(
      pull_request: pull_request,
      requester: requester,
      comment_body: comment_body,
      comment_id: 301484237,
    )
  end

  let(:requester) { "greysteil" }
  let(:pr_comments_url) do
    repo_url + "issues/#{pull_request.github_number}/comments"
  end
  let(:github_comment) { fixture("github_responses/issue_comment.json") }
  let(:comment_body) { "@dependabot ignore this major version" }
  let(:dummy_pr_closer) { instance_double(ClosePullRequest, run: nil) }
  let!(:pull_request) do
    FactoryBot.create(:pull_request, :bump_test, github_number: 122)
  end
  let(:repo) { pull_request.repo }
  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/#{repo.github_id}/" }
  let(:dummy_permission_checker) do
    instance_double(RepoPermissionChecker, permission_level: permission_level)
  end
  let(:permission_level) { "write" }

  before do
    allow(RepoPermissionChecker).
      to receive(:new).and_return(dummy_permission_checker)
  end

  before do
    allow(GitHubHelpers).to receive(:access_token_for)
    allow(ClosePullRequest).to receive(:new).and_return(dummy_pr_closer)
    stub_request(:post, pr_comments_url).
      to_return(status: 200, body: github_comment, headers: json_header)
  end

  it "creates an ignore_condition" do
    expect { action.run }.to change(IgnoreCondition, :count).by(1)
    expect(WebMock).
      to(
        have_requested(:post, pr_comments_url).
        with { |request| expect(request.body).to include("1.x.x") },
      )
  end

  context "when the repo is using a config file" do
    before do
      pull_request.repo.update!(config_file_path: ".github/dependabot.yml")
    end

    it "creates an ignore_condition" do
      expect { action.run }.to change(IgnoreCondition, :count).by(1)
      expect(WebMock).
        to(
          have_requested(:post, pr_comments_url).
          with { |request| expect(request.body).to include("1.x.x") },
        )
    end

    context "that is being used for ignore conditions" do
      before do
        FactoryBot.create(
          :ignore_condition,
          version_requirement: "< 2, > 1.3.0",
          dependency_name: "unrelated",
          update_config: pull_request.update_config,
          from_config_file: true,
        )
      end

      it "creates an ignore_condition" do
        expect { action.run }.to change(IgnoreCondition, :count).by(1)
        expect(WebMock).
          to(
            have_requested(:post, pr_comments_url).
            with { |request| expect(request.body).to include("1.x.x") },
          )
      end
    end
  end

  context "and the PR has a git dependency" do
    let!(:pull_request) do
      FactoryBot.create(
        :pull_request, :bump_test,
        github_number: 122,
        dependencies: [{
          name: "business",
          version: "04fce559673684af8ec2912457a9d6380ea90314",
          previous_version: "b5f3b2839c48c53f9641d6bb1bccafc5260c7620",
        }],
      )
    end

    it "does not create an ignore_condition" do
      expect { action.run }.not_to change(IgnoreCondition, :count)
      expect(WebMock).to(
        have_requested(:post, pr_comments_url).
        with { |request| expect(request.body).to include("stores their SHA") },
      )
    end
  end

  context "and the PR has multiple dependencies" do
    let!(:pull_request) do
      FactoryBot.create(
        :pull_request, :bump_test,
        github_number: 122,
        dependencies: [{
          name: "business",
          version: "2.0.0",
          previous_version: "1.8.0",
        }, {
          name: "statesman",
          version: "3.0.0",
          previous_version: "2.1.0",
        },],
      )
    end

    it "does not create an ignore_condition" do
      expect { action.run }.not_to change(IgnoreCondition, :count)
      expect(WebMock).to(
        have_requested(:post, pr_comments_url).
        with { |request| expect(request.body).to include("single-dependency") },
      )
    end

    context "that are updating to the save version" do
      let!(:pull_request) do
        FactoryBot.create(
          :pull_request, :bump_test,
          github_number: 122,
          dependencies: [{
            name: "business",
            version: "3.0.1",
            previous_version: "1.8.0",
          }, {
            name: "statesman",
            version: "3.0.1",
            previous_version: "2.1.0",
          },],
        )
      end

      it "creates two ignore_condition" do
        expect { action.run }.to change(IgnoreCondition, :count).by(2)
        expect(WebMock).
          to(
            have_requested(:post, pr_comments_url).
            with { |request| expect(request.body).to include("3.x.x") },
          )
      end
    end
  end

  context "and the PR has non-numeric versions" do
    let!(:pull_request) do
      FactoryBot.create(
        :pull_request, :bump_test,
        github_number: 122,
        dependencies: [{
          name: "business",
          version: "01zssadf1",
          previous_version: "a871af12",
        }],
      )
    end

    it "does not create an ignore_condition or comment" do
      expect { action.run }.not_to change(IgnoreCondition, :count)
      expect(WebMock).not_to have_requested(:post, pr_comments_url)
    end
  end

  context "and the ignore already exists" do
    before do
      FactoryBot.create(
        :ignore_condition,
        version_requirement: "< 2, > 1.3.0",
        dependency_name: "business",
        update_config: pull_request.update_config,
      )
    end

    it "does not create an ignore_condition" do
      expect { action.run }.not_to change(IgnoreCondition, :count)
    end
  end

  context "specifying the minor version" do
    let(:comment_body) { "@dependabot ignore this minor version" }

    it "creates the right ignore_condition" do
      expect { action.run }.to change(IgnoreCondition, :count).by(1)
      expect(IgnoreCondition.last.parsed_version_requirements).
        to eq([Gem::Requirement.new(">= 1.8.a", "< 1.9")])
      expect(WebMock).
        to(
          have_requested(:post, pr_comments_url).
            with { |request| expect(request.body).to include("1.8.x") },
        )
    end

    context "that is the current minor version" do
      let!(:pull_request) do
        FactoryBot.create(
          :pull_request, :bump_test,
          github_number: 122,
          dependencies: [{
            name: "business",
            version: "1.8.5",
            previous_version: "1.8.0",
          }],
        )
      end

      it "creates the right ignore_condition" do
        expect { action.run }.to change(IgnoreCondition, :count).by(1)
        expect(IgnoreCondition.last.parsed_version_requirements).
          to eq([Gem::Requirement.new("< 1.9", "> 1.8.0")])
      end
    end
  end

  context "specifying the dependency name with special characters" do
    context "when ignoring one major version dependency from group pr that contains an @ character" do
      let(:comment_body) { "@dependabot ignore @typescript-eslint/parser major version" }
      let(:dependency_name) { "@typescript-eslint/parser" }
      let!(:pull_request) do
        FactoryBot.create(
          :pull_request, :bump_test,
          github_number: 122,
          grouped_update: true,
          dependencies: [{
            name: "@typescript-eslint/parser",
            version: "1.8.5",
            previous_version: "1.8.0",
          }, {
            name: "statesman",
            version: "3.0.0",
            previous_version: "2.1.0",
          },],
        )
      end

      it "creates an ignore_condition" do
        expect { action.run }.to change(IgnoreCondition, :count).by(1)
        last_req = IgnoreCondition.order(:dependency_name).last
        expect(last_req.parsed_version_requirements).
          to eq([Gem::Requirement.new("< 2", "> 1.8.0")])
        expect(action.send(:ignore_comment)).
          to eq("@dependabot ignore @typescript-eslint/parser major version")
      end
    end

    context "when ignoring one minor version dependency from group pr that contains dots and slashes" do
      let(:comment_body) { "@dependabot ignore rsc.io/quote minor version" }
      let(:dependency_name) { "rsc.io/quote" }
      let!(:pull_request) do
        FactoryBot.create(
          :pull_request, :bump_test,
          github_number: 122,
          grouped_update: true,
          dependencies: [{
            name: "rsc.io/quote",
            version: "1.8.5",
            previous_version: "1.8.0",
          }, {
            name: "statesman",
            version: "3.0.0",
            previous_version: "2.1.0",
          },],
        )
      end

      it "creates an ignore_condition" do
        expect { action.run }.to change(IgnoreCondition, :count).by(1)
        last_req = IgnoreCondition.order(:dependency_name).last
        expect(last_req.parsed_version_requirements).
          to eq([Gem::Requirement.new("< 1.9", "> 1.8.0")])
        expect(action.send(:ignore_comment)).
          to eq("@dependabot ignore rsc.io/quote minor version")
      end
    end

    context "when ignoring one major version dependency from a group pr that contains uppercase characters" do
      let(:comment_body) { "@dependabot ignore Microsoft.AspNetCore.DataProtection.EntityFrameworkCore major version" }
      let(:dependency_name) { "Microsoft.AspNetCore.DataProtection.EntityFrameworkCore" }
      let!(:pull_request) do
        FactoryBot.create(
          :pull_request, :bump_test,
          github_number: 122,
          grouped_update: true,
          dependencies: [{
            name: "Microsoft.AspNetCore.DataProtection.EntityFrameworkCore",
            version: "1.8.5",
            previous_version: "1.8.0",
          }, {
            name: "statesman",
            version: "3.0.0",
            previous_version: "2.1.0",
          },],
        )
      end

      it "creates an ignore_condition" do
        expect { action.run }.to change(IgnoreCondition, :count).by(1)
        last_req = IgnoreCondition.order(:dependency_name).last
        expect(last_req.parsed_version_requirements).
          to eq([Gem::Requirement.new("< 2", "> 1.8.0")])
        expect(action.send(:ignore_comment)).
          to eq("@dependabot ignore microsoft.aspnetcore.dataprotection.entityframeworkcore major version")
      end
    end
  end

  context "specifying the dependency name minor version" do
    let(:comment_body) { "@dependabot ignore business minor version" }

    context "when ignoring one minor version dependency from group pr" do
      let(:dependency_name) { "business" }
      let!(:pull_request) do
        FactoryBot.create(
          :pull_request, :bump_test,
          github_number: 122,
          grouped_update: true,
          dependencies: [{
            name: "business",
            version: "1.8.5",
            previous_version: "1.8.0",
          }, {
            name: "statesman",
            version: "3.0.0",
            previous_version: "2.1.0",
          },],
        )
      end

      it "creates an ignore_condition" do
        expect { action.run }.to change(IgnoreCondition, :count).by(1)
        last_req = IgnoreCondition.order(:dependency_name).last
        expect(last_req.parsed_version_requirements).
          to eq([Gem::Requirement.new("< 1.9", "> 1.8.0")])
      end
    end
  end

  context "specifying the patch version" do
    let(:comment_body) { "@dependabot ignore this patch version" }

    it "creates the right ignore_condition" do
      expect { action.run }.to change(IgnoreCondition, :count).by(1)
      expect(IgnoreCondition.last.parsed_version_requirements).
        to eq([Gem::Requirement.new(">= 1.8.0.a", "< 1.8.1")])
      expect(WebMock).
        to(
          have_requested(:post, pr_comments_url).
          with { |request| expect(request.body).to include("1.8.0 ") },
        )
    end
  end

  context "specifying the major version" do
    let(:comment_body) { "@dependabot ignore this major version" }

    it "creates the right ignore_condition" do
      expect { action.run }.to change(IgnoreCondition, :count).by(1)
      expect(IgnoreCondition.last.parsed_version_requirements).
        to eq([Gem::Requirement.new("< 2", "> 1.3.0")])
      expect(WebMock).
        to(
          have_requested(:post, pr_comments_url).
          with { |request| expect(request.body).to include("1.x.x") },
        )
    end

    context "when only updating by a patch version" do
      let!(:pull_request) do
        FactoryBot.create(
          :pull_request, :bump_test,
          github_number: 122,
          dependencies: [{
            name: "business",
            version: "1.8.5",
            previous_version: "1.8.1",
          }],
        )
      end

      it "creates the right ignore_condition" do
        expect { action.run }.to change(IgnoreCondition, :count).by(1)
        expect(IgnoreCondition.last.parsed_version_requirements).
          to eq([Gem::Requirement.new("< 2", "> 1.8.1")])
      end
    end
  end

  context "specifying the dependency name major version in a grouped update PR" do
    let(:comment_body) { "@dependabot ignore business major version" }

    context "when ignoring one major version dependency from group pr" do
      let(:dependency_name) { "business" }
      let!(:pull_request) do
        FactoryBot.create(
          :pull_request, :bump_test,
          github_number: 122,
          grouped_update: true,
          dependencies: [{
            name: "business",
            version: "1.8.5",
            previous_version: "1.8.1",
          }, {
            name: "statesman",
            version: "3.0.0",
            previous_version: "2.1.0",
          },],
        )
      end

      it "creates an ignore_condition" do
        expect { action.run }.to change(IgnoreCondition, :count).by(1)
        last_req = IgnoreCondition.order(:dependency_name).last
        expect(last_req.parsed_version_requirements).
          to eq([Gem::Requirement.new("< 2", "> 1.8.1")])
        expect(WebMock).
          to(
            have_requested(:post, pr_comments_url).
            with do |request|
              expect(request.body).
            to include("OK, I won't notify you about version 1.x.x of business")
            end,
          )
      end
    end
  end

  context "specifying all versions" do
    let(:comment_body) { "@dependabot ignore this dependency" }

    it "creates the right ignore_condition" do
      expect { action.run }.to change(IgnoreCondition, :count).by(1)
      expect(IgnoreCondition.last.parsed_version_requirements).
        to eq([Gem::Requirement.new("> 1.3.0")])
      expect(WebMock).
        to(
          have_requested(:post, pr_comments_url).
          with do |request|
            expect(request.body).to include("notify you about business")
          end,
        )
    end

    context "using `package` rather than `dependency`" do
      let(:comment_body) { "@dependabot ignore this package" }

      it "creates the right ignore_condition" do
        expect { action.run }.to change(IgnoreCondition, :count).by(1)
        expect(IgnoreCondition.last.parsed_version_requirements).
          to eq([Gem::Requirement.new("> 1.3.0")])
        expect(WebMock).
          to(
            have_requested(:post, pr_comments_url).
            with do |request|
              expect(request.body).to include("notify you about business")
            end,
          )
      end
    end

    context "and the PR has non-numeric versions" do
      let!(:pull_request) do
        FactoryBot.create(
          :pull_request, :bump_test,
          github_number: 122,
          dependencies: [{
            name: "business",
            version: "01zssadf1",
            previous_version: "a871af12",
          }],
        )
      end

      it "creates an ignore_condition" do
        expect { action.run }.to change(IgnoreCondition, :count).by(1)
        expect(IgnoreCondition.last.parsed_version_requirements).
          to eq([Gem::Requirement.new(">= 0")])
        expect(WebMock).
          to(
            have_requested(:post, pr_comments_url).
            with do |request|
              expect(request.body).to include("notify you about business")
            end,
          )
      end
    end

    context "and the PR has multiple dependencies" do
      let!(:pull_request) do
        FactoryBot.create(
          :pull_request, :bump_test,
          github_number: 122,
          dependencies: [{
            name: "business",
            version: "2.0.0",
            previous_version: "1.8.0",
          }, {
            name: "statesman",
            version: "3.0.0",
            previous_version: "2.1.0",
          },],
        )
      end

      it "creates an ignore_condition" do
        expect { action.run }.to change(IgnoreCondition, :count).by(2)
        last_req = IgnoreCondition.order(:dependency_name).last
        expect(last_req.parsed_version_requirements).
          to eq([Gem::Requirement.new("> 2.1.0")])
        expect(WebMock).
          to(
            have_requested(:post, pr_comments_url).
            with do |request|
              expect(request.body).to include("any of these dependencies")
            end,
          )
      end
    end

    context "and the PR has a removed transitive dependency" do
      let!(:pull_request) do
        FactoryBot.create(
          :pull_request, :bump_test,
          github_number: 122,
          dependencies: [{
            name: "removed",
            previous_version: "1.8.0",
            removed: true,
          }, {
            name: "parent",
            version: "3.0.0",
            previous_version: "2.1.0",
          },],
        )
      end

      it "creates ignore_conditions" do
        expect { action.run }.to change(IgnoreCondition, :count).by(2)
        expect(WebMock).
          to(
            have_requested(:post, pr_comments_url).
            with do |request|
              expect(request.body).to include("any of these dependencies")
            end,
          )
      end
    end
  end

  context "specifying the dependency name in a group update pr" do
    let(:comment_body) { "@dependabot ignore business" }
    let!(:pull_request) do
      FactoryBot.create(
        :pull_request, :bump_test,
        github_number: 122,
        grouped_update: true,
        dependencies: [{
          name: "business",
          version: "1.8.0",
          previous_version: "1.3.0",
        }, {
          name: "statesman",
          version: "3.0.1",
          previous_version: "2.1.0",
        },],
      )
    end

    it "creates the right ignore_condition" do
      expect { action.run }.to change(IgnoreCondition, :count).by(1)
      expect(IgnoreCondition.last.parsed_version_requirements).
        to eq([Gem::Requirement.new("> 1.3.0")])
      expect(WebMock).
        to(
          have_requested(:post, pr_comments_url).
          with do |request|
            expect(request.body).to include("notify you about business")
          end,
        )
    end

    context "using `package` rather than `dependency`" do
      let(:comment_body) { "@dependabot ignore business package" }

      it "creates the right ignore_condition" do
        expect { action.run }.to change(IgnoreCondition, :count).by(1)
        expect(IgnoreCondition.last.parsed_version_requirements).
          to eq([Gem::Requirement.new("> 1.3.0")])
        expect(WebMock).
          to(
            have_requested(:post, pr_comments_url).
            with do |request|
              expect(request.body).to include("notify you about business")
            end,
          )
      end
    end

    context "and the PR has non-numeric versions" do
      let!(:pull_request) do
        FactoryBot.create(
          :pull_request, :bump_test,
          github_number: 122,
          grouped_update: true,
          dependencies: [{
            name: "business",
            version: "01zssadf1",
            previous_version: "a871af12",
          }, {
            name: "statesman",
            version: "3.0.1",
            previous_version: "2.1.0",
          },],
        )
      end

      it "creates an ignore_condition" do
        expect { action.run }.to change(IgnoreCondition, :count).by(1)
        expect(IgnoreCondition.last.parsed_version_requirements).
          to eq([Gem::Requirement.new(">= 0")])
        expect(WebMock).
          to(
            have_requested(:post, pr_comments_url).
            with do |request|
              expect(request.body).to include("notify you about business")
            end,
          )
      end
    end

    context "and the PR has single dependency" do
      let!(:pull_request) do
        FactoryBot.create(
          :pull_request, :bump_test,
          github_number: 122,
          grouped_update: true,
          dependencies: [{
            name: "business",
            version: "3.1.0",
            previous_version: "2.1.0",
          }],
        )
      end

      it "creates an ignore_condition" do
        expect { action.run }.to change(IgnoreCondition, :count).by(1)
        last_req = IgnoreCondition.order(:dependency_name).last
        expect(last_req.parsed_version_requirements).
          to eq([Gem::Requirement.new("> 2.1.0")])
        expect(WebMock).
          to(
            have_requested(:post, pr_comments_url).
            with do |request|
              expect(request.body).to include("OK, I won't notify you about business again")
            end,
          )
      end
    end
  end

  context "with random whitespace" do
    let(:comment_body) { "   @dependabot   ignore  this major version  " }

    it "creates an ignore_condition" do
      expect { action.run }.to change(IgnoreCondition, :count).by(1)
    end
  end

  shared_examples "does not create ignore condition" do |comment|
    let(:comment_body) { comment }

    it "for #{comment}" do
      expect { action.run }.not_to change(IgnoreCondition, :count)
      expect(dummy_pr_closer).not_to have_received(:run)
    end
  end

  context "when non grouped update pr given grouped update pr ignore command" do
    let!(:pull_request) do
      FactoryBot.create(
        :pull_request, :bump_test,
        github_number: 122,
        dependencies: [{
          name: "business",
          version: "2.0.0",
          previous_version: "1.8.0",
        }],
      )
    end

    it_behaves_like "does not create ignore condition", "@dependabot ignore business major version"
    it_behaves_like "does not create ignore condition", "@dependabot ignore business minor version"
    it_behaves_like "does not create ignore condition", "@dependabot ignore business"
  end

  context "when grouped update pr given non grouped update pr ignore command" do
    let!(:pull_request) do
      FactoryBot.create(
        :pull_request, :bump_test,
        github_number: 122,
        grouped_update: true,
        dependencies: [{
          name: "business",
          version: "2.0.0",
          previous_version: "1.8.0",
        }, {
          name: "statesman",
          version: "3.0.0",
          previous_version: "2.1.0",
        },],
      )
    end

    it_behaves_like "does not create ignore condition", "@dependabot ignore this major version"
    it_behaves_like "does not create ignore condition", "@dependabot ignore this minor version"
    it_behaves_like "does not create ignore condition", "@dependabot ignore this dependency"
  end

  context "when pull request is a grouped update pr" do
    let(:comment_body) { "@dependabot ignore business major version" }
    let!(:pull_request) do
      FactoryBot.create(
        :pull_request, :bump_test,
        github_number: 122,
        grouped_update: true,
        dependencies: [{
          name: "business",
          version: "2.0.0",
          previous_version: "1.8.0",
        }, {
          name: "statesman",
          version: "3.0.0",
          previous_version: "2.1.0",
        },],
      )
    end

    context "with many dependencies" do
      it "creates an ignore_condition and recreates the PR" do
        expect { action.run }.to change(IgnoreCondition, :count).by(1)
        expect(dummy_pr_closer).not_to have_received(:run)
      end
    end

    context "with an incorrect dependency name" do
      let(:comment_body) { "@dependabot ignore foobar major version" }

      it "creates does not ignore_condition" do
        expect { action.run }.to change(IgnoreCondition, :count).by(0)
        expect(dummy_pr_closer).not_to have_received(:run)
      end
    end

    context "with a single dependency" do
      before do
        dep_name = pull_request.updated_dependencies.find_by(name: "statesman")
        pull_request.updated_dependencies.destroy(dep_name)
      end

      it "creates an ignore_condition and closes the PR" do
        expect { action.run }.to change(IgnoreCondition, :count).by(1)
        expect(dummy_pr_closer).to have_received(:run)
      end
    end
  end

  context "validate ignore commands " do
    let!(:pull_request) do
      FactoryBot.create(
        :pull_request, :bump_test,
        github_number: 122,
        dependencies: [{
          name: "business",
          version: "2.0.0",
          previous_version: "1.8.0",
        }],
      )
    end

    let(:comment_body) { "@dependabot ignore this major version" }
    let(:handle_ignore_request) do
      described_class.new(
        pull_request: pull_request,
        requester: "greysteil",
        comment_body: :comment_body,
        comment_id: 1
      )
    end

    context "when pull request is a non grouped update" do
      before do
        allow(handle_ignore_request).to receive(:validate_command).and_return(false)
      end

      it "calls CreateComment with a valid command hints for non-group updates pr" do
        valid_command_hint = "For single dependency PRs, use commands like:\n" \
                             "`@dependabot ignore this major version`\n" \
                             "`@dependabot ignore this minor version`\n" \
                             "`@dependabot ignore this dependency`"

        msg = "Sorry, the command you entered is not valid for this pull request. " \
              "Please check the syntax and try again. \n\nValid commands:\n#{valid_command_hint}"

        expect(CreateComment).to receive(:new).with(
          pull_request: pull_request,
          comment_body: msg
        ).and_call_original

        handle_ignore_request.run
      end
    end

    context "when pull request is a grouped update" do
      before do
        pull_request.grouped_update = true
        allow(handle_ignore_request).to receive(:validate_command).and_return(false)
      end

      it "calls CreateComment with a valid command hints for grouped updates pr" do
        valid_command_hint = "For grouped and multi-dependency PRs, use commands like:\n" \
                             "`@dependabot ignore <dependency name> major version`\n" \
                             "`@dependabot ignore <dependency name> minor version`\n" \
                             "`@dependabot ignore these dependencies`\n" \
                             "`@dependabot ignore <dependency name>`"

        msg = "Sorry, the command you entered is not valid for this pull request. " \
              "Please check the syntax and try again. \n\nValid commands:\n#{valid_command_hint}"

        expect(CreateComment).to receive(:new).with(
          pull_request: pull_request,
          comment_body: msg
        ).and_call_original

        handle_ignore_request.run
      end
    end
  end
end
