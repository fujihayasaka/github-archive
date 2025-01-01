# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityCampaignsAlertBranchesControllerTest < GitHub::IntegrationTestCase
  include HydroTestHelpers

  fixtures do
    @code_scanning_integration = create(:code_scanning_integration)
    @code_scanning_bot = @code_scanning_integration.bot

    @user = create(:user)
    @unauthed_user = create(:user, skip_enterprise_managed_user: true)

    @org = create(:business_plus_organization, admin: @user)
    @org.advanced_security_billable_entity&.mark_advanced_security_as_purchased_for_entity(actor: @user)

    @repo = create(:private_repository, owner: @org)

    @security_campaign = create(:security_campaign, organization: @org)

    create(:security_campaign_alert, repository: @repo, security_campaign: @security_campaign, logical_alert_number: 2)
    create(:security_campaign_alert, repository: @repo, security_campaign: @security_campaign, logical_alert_number: 6)
  end

  setup do
    GitHub.flipper[:security_campaigns].enable

    if GitHub.enterprise?
      GitHub.stubs(:actions_enabled?).returns(true)
      GitHub.stubs(:code_scanning_enabled?).returns(true)
    else
      @org.advanced_security_billable_entity.mark_advanced_security_as_purchased_for_entity(actor: @user)
    end

    CodeScanning::Autofix.stubs(:available_in_environment?).returns(true)

    example_repo :security_campaigns_autofixes, @repo
    @existing_branch_name = "existing-branch-name"
    @repo.heads.create(@existing_branch_name, @repo.default_branch_ref.commit.oid, @user)

    @repo.enable_advanced_security!(actor: @user)

    @new_branch_params = {
      "name" => "new-branch-name",
      "create_new_branch" => true,
      "alert_numbers" => [2, 6]
    }

    @existing_branch_params = {
      "name" => @existing_branch_name,
      "create_new_branch" => false,
      "alert_numbers" => [2, 6],
      "commit_autofix_suggestions" => true
    }
  end

  context "#create" do
    test "returns 404 when feature flag is disabled" do
      GitHub.flipper[:security_campaigns].disable

      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/branches", params: @new_branch_params, xhr: true

      assert_response_not_found
    end

    test "returns 404 for users that don't have access to the repo" do
      request_env["HTTP_ACCEPT"] = "application/json"
      as @unauthed_user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/branches", params: @new_branch_params, xhr: true

      assert_response_not_found
    end

    test "returns 404 for public repository", skip_with_all_emus: true do
      public_repo = create(:public_repository, from_example: :simple, owner: @org)
      create(:security_campaign_alert, repository: public_repo, security_campaign: @security_campaign, logical_alert_number: 5)

      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{public_repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/branches", params: @new_branch_params, xhr: true

      assert_response_not_found
    end

    test "returns 422 if campaign is closed" do
      @security_campaign.update(closed_at: Time.now)

      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/branches", params: @new_branch_params, xhr: true

      assert_response :unprocessable_entity
      payload = JSON.parse(response.body)
      assert_equal "Campaign is closed", payload["message"]
    end

    test "creates a new branch without autofixes" do
      GitHub::Turboscan::SuggestedFixes.expects(:suggested_fix).never

      GitHub::Turboscan.expects(:create_alert_links).once.with(
        repository_id: @repo.id,
        alert_numbers: @new_branch_params["alert_numbers"],
        ref_name_bytes: "refs/heads/new-branch-name".b,
      ).returns(Twirp::ClientResp.new(
        data: Turboscan::Proto::CreateAlertLinksResponse.new
      ))

      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/branches", params: @new_branch_params, xhr: true

      assert_response :ok

      payload = JSON.parse(response.body)

      assert_equal ({ "branchName" => "new-branch-name", "pullRequestPath" => nil, "messages" => [] }), payload

      new_branch = @repo.heads.find("new-branch-name")
      refute_nil new_branch
      assert_equal @repo.default_branch_ref.commit.oid, new_branch.commit.oid
    end

    test "creates a new branch with autofixes" do
      GitHub::Turboscan.expects(:alerts_by_repo).returns(alerts_by_repo_response)
      GitHub::Turboscan::SuggestedFixes.expects(:suggested_fix).returns(suggested_fix_response)
      GitHub::Turboscan.expects(:create_alert_links).once.with(
        repository_id: @repo.id,
        alert_numbers: @new_branch_params["alert_numbers"],
        ref_name_bytes: "refs/heads/new-branch-name".b,
      ).returns(Twirp::ClientResp.new(
        data: Turboscan::Proto::CreateAlertLinksResponse.new
      ))

      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/branches", params: @new_branch_params.merge({
        "commit_autofix_suggestions" => true,
      }), xhr: true

      assert_response :ok

      payload = JSON.parse(response.body)

      assert_equal ({ "branchName" => "new-branch-name", "pullRequestPath" => nil, "messages" => [] }), payload

      new_branch = @repo.heads.find("new-branch-name")
      refute_nil new_branch
      refute_equal @repo.default_branch_ref.commit.oid, new_branch.commit.oid

      new_commits = @repo.commits.history(new_branch.target_oid, 3)
      assert_equal 3, new_commits.size
      assert_equal @repo.default_branch_ref.commit.oid, new_commits.last.oid
      assert_equal "Apply code scanning fix for reflected xss", new_commits.first.short_message_text
      assert_equal "Apply code scanning fix for reflected xss", new_commits.second.short_message_text
    end

    test "applies autofixes to an existing branch" do
      GitHub::Turboscan.expects(:alerts_by_repo).returns(alerts_by_repo_response)
      GitHub::Turboscan::SuggestedFixes.expects(:suggested_fix).returns(suggested_fix_response)
      GitHub::Turboscan.expects(:create_alert_links).once.with(
        repository_id: @repo.id,
        alert_numbers: @new_branch_params["alert_numbers"],
        ref_name_bytes: "refs/heads/#{@existing_branch_name}".b,
      ).returns(Twirp::ClientResp.new(
        data: Turboscan::Proto::CreateAlertLinksResponse.new
      ))

      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/branches", params: @existing_branch_params, xhr: true

      assert_response :ok

      payload = JSON.parse(response.body)

      assert_equal ({ "branchName" => @existing_branch_name, "pullRequestPath" => nil, "messages" => [] }), payload

      existing_branch = @repo.heads.find(@existing_branch_name)
      refute_nil existing_branch
      refute_equal @repo.default_branch_ref.commit.oid, existing_branch.commit.oid

      new_commits = @repo.commits.history(existing_branch.target_oid, 3)
      assert_equal 3, new_commits.size
      assert_equal @repo.default_branch_ref.commit.oid, new_commits.last.oid
      assert_equal "Apply code scanning fix for reflected xss", new_commits.first.short_message_text
      assert_equal "Apply code scanning fix for reflected xss", new_commits.second.short_message_text
    end

    test "creates a draft PR with autofixes" do
      GitHub::Turboscan.expects(:alerts_by_repo).returns(alerts_by_repo_response)
      GitHub::Turboscan::SuggestedFixes.expects(:suggested_fix).returns(suggested_fix_response)
      GitHub::Turboscan.expects(:create_alert_links).once.with do |args|
        args == {
          repository_id: @repo.id,
          alert_numbers: @new_branch_params["alert_numbers"],
          pull_request_id: @repo.pull_requests.find_by(head_ref: "pr-test-branch").id,
        }
      end.returns(Twirp::ClientResp.new(
        data: Turboscan::Proto::CreateAlertLinksResponse.new
      ))

      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/branches", params: @new_branch_params.merge({
        "commit_autofix_suggestions" => true, "create_draft_pr" => true, "name" => "pr-test-branch"
      }), xhr: true

      assert_response :ok

      payload = JSON.parse(response.body)
      pull_request = @repo.pull_requests.find_by(head_ref: "pr-test-branch")

      assert_equal ({ "branchName" => "pr-test-branch", "pullRequestPath" => "/#{@repo.name_with_display_owner}/pull/#{pull_request.number}", "messages" => [] }), payload
      assert_equal "Fix 2 code scanning alerts", pull_request.title
      assert_equal "Fixes 2 code scanning alerts:\n- #{GitHub.url}/#{@repo.name_with_display_owner}/security/code-scanning/2\n- #{GitHub.url}/#{@repo.name_with_display_owner}/security/code-scanning/6\n", pull_request.body
      assert_equal pull_request.draft?, true
      assert_equal pull_request.user, @user
    end

    test "publishes an analytics event", skip_enterprise: true do
      GitHub::Turboscan::SuggestedFixes.expects(:suggested_fix).never

      GitHub::Turboscan.expects(:create_alert_links).once.with(
        repository_id: @repo.id,
        alert_numbers: @new_branch_params["alert_numbers"],
        ref_name_bytes: "refs/heads/new-branch-name".b,
      ).returns(Twirp::ClientResp.new(
        data: Turboscan::Proto::CreateAlertLinksResponse.new
      ))

      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/branches", params: @new_branch_params, xhr: true

      assert_response :ok

      assert_hydro_published_partial({
        category: "security_campaigns",
        action: "create_branch",
        label: "security_campaign_id:#{@security_campaign.id}; alert_numbers_count:2; commit_suggested_fixes:false; create_draft_pr:false",
      }, schema: "github.analytics.v0.Event")
    end

    test "applies autofixes to an existing branch with an existing PR" do
      @repo.heads.find(@existing_branch_name).append_commit({ message: "add file", author: @user }, @user) do |changes|
        changes.add("a_file.txt", "content")
      end

      pull = create(:pull_request,
        repository: @repo,
        base_repository: @repo,
        base_ref: @repo.default_branch,
        head_repository: @repo,
        head_ref: @existing_branch_name,
        user: @user,
      )

      GitHub::Turboscan.expects(:alerts_by_repo).returns(alerts_by_repo_response)
      GitHub::Turboscan::SuggestedFixes.expects(:suggested_fix).returns(suggested_fix_response)
      GitHub::Turboscan.expects(:create_alert_links).once.with(
        repository_id: @repo.id,
        alert_numbers: @new_branch_params["alert_numbers"],
        pull_request_id: pull.id,
      ).returns(Twirp::ClientResp.new(
        data: Turboscan::Proto::CreateAlertLinksResponse.new
      ))

      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/branches", params: @existing_branch_params, xhr: true

      assert_response :ok

      payload = JSON.parse(response.body)

      assert_equal ({ "branchName" => @existing_branch_name, "pullRequestPath" => nil, "messages" => [] }), payload

      # Make sure we don't see cached ref data
      @repo.reload

      existing_branch = @repo.heads.find(@existing_branch_name)
      refute_nil existing_branch
      refute_equal @repo.default_branch_ref.commit.oid, existing_branch.commit.oid

      new_commits = @repo.commits.history(existing_branch.target_oid, 4)
      assert_equal 4, new_commits.size
      assert_equal "Apply code scanning fix for reflected xss", new_commits[0].short_message_text
      assert_equal "Apply code scanning fix for reflected xss", new_commits[1].short_message_text
      assert_equal "add file", new_commits[2].short_message_text
      assert_equal @repo.default_branch_ref.commit.oid, new_commits[3].oid
    end

    test "creates a new branch with a normalized name" do
      GitHub::Turboscan.expects(:create_alert_links).once.with(
        repository_id: @repo.id,
        alert_numbers: @new_branch_params["alert_numbers"],
        ref_name_bytes: "refs/heads/Aridiculous3branch.@NAME/more".b,
      ).returns(Twirp::ClientResp.new(
        data: Turboscan::Proto::CreateAlertLinksResponse.new
      ))

      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/branches", params: @new_branch_params.merge({
        "name" => ".A?*ridiculous*3branch.@NAME/more/",
      }), xhr: true

      assert_response :ok

      payload = JSON.parse(response.body)

      assert_equal ({ "branchName" => "Aridiculous3branch.@NAME/more", "pullRequestPath" => nil, "messages" => [] }), payload

      new_branch = @repo.heads.find("Aridiculous3branch.@NAME/more")
      refute_nil new_branch
      assert_equal @repo.default_branch_ref.commit.oid, new_branch.commit.oid
    end

    test "returns 422 when the name is empty" do
      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/branches", params: @new_branch_params.merge(
        name: ""
      ), xhr: true

      assert_response :unprocessable_entity

      payload = JSON.parse(response.body)
      assert_equal "Branch name is required", payload["message"]
    end

    test "returns 422 when the default branch does not exist" do
      empty_repo = create(:private_repository, owner: @org)
      empty_repo.enable_advanced_security!(actor: @user)

      create(:security_campaign_alert, repository: empty_repo, security_campaign: @security_campaign, logical_alert_number: 2)
      create(:security_campaign_alert, repository: empty_repo, security_campaign: @security_campaign, logical_alert_number: 6)

      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{empty_repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/branches", params: @new_branch_params, xhr: true

      assert_response :unprocessable_entity

      payload = JSON.parse(response.body)
      assert_equal "Default branch must exist", payload["message"]
    end

    test "returns 422 when trying to create a new branch but the branch already exists" do
      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/branches", params: @new_branch_params.merge({
        "name" => @existing_branch_name,
      }), xhr: true

      assert_response :unprocessable_entity

      payload = JSON.parse(response.body)
      assert_equal "Branch already exists", payload["message"]
    end

    test "returns 422 if trying to use an existing branch but it doesn't exist" do
      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/branches", params: @existing_branch_params.merge({
        "name" => "non-existent-branch",
      }), xhr: true

      assert_response :unprocessable_entity

      payload = JSON.parse(response.body)
      assert_equal "Branch does not exist", payload["message"]
    end

    test "returns 422 when the branch name is invalid" do
      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/branches", params: @new_branch_params.merge({
        "name" => "refs/heads/refs/foo", # Branch names cannot start with refs/
      }), xhr: true

      assert_response :unprocessable_entity

      payload = JSON.parse(response.body)
      assert_equal "Invalid branch name", payload["message"]
    end

    test "returns 422 when the alert numbers are not an array" do
      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/branches", params: @new_branch_params.merge({
        "alert_numbers" => 1
      }), xhr: true

      assert_response :unprocessable_entity

      payload = JSON.parse(response.body)
      assert_equal "Alert numbers are required", payload["message"]
    end

    test "returns 422 when the alert numbers are strings" do
      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/branches", params: @new_branch_params.merge({
        "alert_numbers" => %w[foo bar]
      }), xhr: true

      assert_response :unprocessable_entity

      payload = JSON.parse(response.body)
      assert_equal "Invalid alert numbers", payload["message"]
    end

    test "returns 422 when the alert numbers are negative numbers" do
      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/branches", params: @new_branch_params.merge({
        "alert_numbers" => ["-1", 2, "4"]
      }), xhr: true

      assert_response :unprocessable_entity

      payload = JSON.parse(response.body)
      assert_equal "Invalid alert numbers", payload["message"]
    end

    test "returns 422 if not creating a new branch and also not committing autofixes" do
      request_env["HTTP_ACCEPT"] = "application/json"
      as @user
      post "/#{@repo.name_with_display_owner}/security/campaigns/#{@security_campaign.number}/branches", params: @existing_branch_params.merge({
        "commit_autofix_suggestions" => false,
      }), xhr: true

      assert_response :unprocessable_entity

      payload = JSON.parse(response.body)
      assert_equal "Must make a new branch or commit autofix suggestions", payload["message"]
    end
  end

  def alerts_by_repo_response
    ::Twirp::ClientResp.new(
      data: Turboscan::Proto::AlertsByRepoResponse.new(
        results: [
          Turboscan::Proto::RepoResult.new(
            repository_id: @repo.id,
            result: Turboscan::Proto::Result.new(
              number: 2,
              rule: {
                short_description: "Reflected XSS",
              }
            ),
          ),
          Turboscan::Proto::RepoResult.new(
            repository_id: @repo.id,
            result: Turboscan::Proto::Result.new(
              number: 6,
              rule: {
                short_description: "Reflected XSS",
              }
            ),
          ),
        ]
      )
    )
  end

  def suggested_fix_response
    ::Twirp::ClientResp.new(
      data: Turboscan::Proto::GetSuggestedFixResponse.new(
        suggested_fix_alerts: {
          2 => Turboscan::Proto::SuggestedFixAlert.new(suggested_fix: Turboscan::Proto::SuggestedFix.new(
            outdated: false,
            dismissed: false,
            files: [
              {
                file_path: "app2/package.json",
                diff_content: "diff --git a/app2/package.json b/app2/package.json\n--- a/app2/package.json\n+++ b/app2/package.json\n@@ -5,3 +5,4 @@\n     \"express\": \"^4.19.2\",\n-    \"rimraf\": \"^5.0.7\"\n+    \"rimraf\": \"^5.0.7\",\n+    \"escape-html\": \"^1.0.3\"\n   }\n",
              },
              {
                file_path: "app2/index.js",
                diff_content: "diff --git a/app2/index.js b/app2/index.js\n--- a/app2/index.js\n+++ b/app2/index.js\n@@ -1,8 +1,9 @@\n const express = require(\"express\");\n+const escape = require('escape-html');\n \n const app = express();\n-app.get(\"/\", (req, res) => res.send(`Hello, ${req.query.name}!`));\n+app.get(\"/\", (req, res) => res.send(`Hello, ${escape(req.query.name)}!`));\n \n-app.get(\"/page2\", (req, res) => res.send(`Welcome to page 2, ${req.query.name}!`));\n+app.get(\"/page2\", (req, res) => res.send(`Welcome to page 2, ${escape(req.query.name)}!`));\n \n-app.get(\"/page4\", (req, res) => res.send(`Welcome to page 4, ${req.query.name}!`));\n+app.get(\"/page4\", (req, res) => res.send(`Welcome to page 4, ${escape(req.query.name)}!`));\n",
              },
            ]
          )),
          6 => Turboscan::Proto::SuggestedFixAlert.new(suggested_fix: Turboscan::Proto::SuggestedFix.new(
            outdated: false,
            dismissed: false,
            files: [
              {
                file_path: "app1/index.js",
                diff_content: "diff --git a/app1/index.js b/app1/index.js\n--- a/app1/index.js\n+++ b/app1/index.js\n@@ -1,2 +1,3 @@\n const express = require(\"express\");\n+const escape = require('escape-html');\n const {page6, page7} = require('./routes')\n@@ -4,7 +5,7 @@\n const app = express();\n-app.get(\"/\", (req, res) => res.send(`Hello, ${req.query.name}!`));\n+app.get(\"/\", (req, res) => res.send(`Hello, ${escape(req.query.name)}!`));\n \n-app.get(\"/page2\", (req, res) => res.send(`Welcome to page 2, ${req.query.name}!`));\n+app.get(\"/page2\", (req, res) => res.send(`Welcome to page 2, ${escape(req.query.name)}!`));\n \n-app.get(\"/page4\", (req, res) => res.send(`Welcome to page 4, ${req.query.name}!`));\n+app.get(\"/page4\", (req, res) => res.send(`Welcome to page 4, ${escape(req.query.name)}!`));\n",
              },
              {
                file_path: "app1/package.json",
                diff_content: "diff --git a/app1/package.json b/app1/package.json\n--- a/app1/package.json\n+++ b/app1/package.json\n@@ -3,3 +3,4 @@\n   \"dependencies\": {\n-    \"express\": \"^4.19.2\"\n+    \"express\": \"^4.19.2\",\n+    \"escape-html\": \"^1.0.3\"\n   }\n",
              },
            ]
          ))
        }
      )
    )
  end
end
