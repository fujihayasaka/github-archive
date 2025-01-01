# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"
require "turboscan"

class CodeScanningSerializersTest < Api::SerializerTestCase
  fixtures do
    @repo = create(:private_repository)
    @user = create(:user)
    @owner = create(:paid_user)
    @org = create(:organization, admin: @owner)
  end

  context "#code_scanning_alert_hash" do
    test "constructs hash for a code scanning alert" do

      user = create :user
      org = create(:organization, :zuora, admin: user)
      repo = create(:private_repository, owner: org)
      owner = create(:paid_user)
      org.mark_advanced_security_as_purchased_for_entity(actor: user)

      response = Turbocassette.use("code-scanning/get-alert") do
        GitHub::Turboscan.alert(repository_id: repo.id, number: 1)
      end

      options = {
        repo: @repo,
      }

      output = serialize_hash_method(:code_scanning_alert_hash, response.data.result, options)

      assert_equal "bar", output["rule"]["id"]
      assert_equal "none", output["rule"]["severity"]
      assert_equal "medium", output["rule"]["security_severity_level"]
      assert_equal [], output["rule"]["tags"]
      assert_equal "", output["rule"]["help"]
      assert_equal "", output["rule"]["full_description"]
      assert_equal "https://codeql.github.com/", output["rule"]["help_uri"]
      assert_equal "Something short", output["rule"]["description"]
      assert_equal "CodeQL", output["tool"]["name"]
      assert_nil output["tool"]["display_name"]
      assert_equal "0001-01-01T00:00:00Z", output["created_at"]
      assert_equal "0001-01-01T00:00:00Z", output["updated_at"]
      assert_nil output["open"]
      assert_equal "fixed", output["state"]
      assert_nil output["dismissed_by"]
      assert_nil output["dismissed_at"]
      assert_nil output["dismissed_reason"]
      assert_nil output["dismissed_comment"]
      assert_equal "#{GitHub.api_url}/repos/#{@repo.name_with_owner}/code-scanning/alerts/1", output["url"]
      assert_equal "#{GitHub.url}/#{@repo.name_with_owner}/security/code-scanning/1", output["html_url"]
      assert_equal "refs/heads/ref1", output["most_recent_instance"]["ref"]
      assert_equal ".github/workflows/codeql.yml:CodeQL", output["most_recent_instance"]["analysis_key"]
      assert_equal "{}", output["most_recent_instance"]["environment"]
      assert_equal ".github/workflows/codeql.yml:CodeQL", output["most_recent_instance"]["category"]
      assert_equal "fixed", output["most_recent_instance"]["state"]
      assert_equal "1.0.0", output["tool"]["version"]
      assert_equal "refs/heads/ref1", output["most_recent_instance"]["ref"]
    end

    test "looks up closed_by user from the alert's resolver_id" do
      user = create :user
      org = create(:organization, :zuora, admin: user)
      # Delete the repo with id 19 if it already exists because of other test fixtures
      Repository.where(id: [19]).delete_all
      repo = create(:private_repository, owner: org, id: 19)
      owner = create(:paid_user)
      org.mark_advanced_security_as_purchased_for_entity(actor: user)

      response = VCR.use_cassette("code-scanning/get-alert-2", persist_with: :turboscan) do
        GitHub::Turboscan.alert(repository_id: 19, number: 9)
      end

      # Update the resolver_id to a user id that already exists in the test data
      # This ensures that the response code can lookup a `closed_by` user
      response.data.result.resolver_id = @user.id

      options = {
        repo: @repo,
      }

      output = serialize_hash_method(:code_scanning_alert_hash, response.data.result, options)

      assert_equal @user.login, output["dismissed_by"]["login"]
      assert_equal "0001-01-01T00:00:00Z", output["dismissed_at"]
      assert_equal "used in tests", output["dismissed_reason"]
      assert_equal "This is only used in non-production test code where we can trust the input.", output["dismissed_comment"]
      assert_equal "dismissed", output["most_recent_instance"]["state"]
      assert_equal ["external/cwe/cwe-601", "security"], output["rule"]["tags"]
      assert_equal "", output["rule"]["help"]
      assert_equal "Server-side URL redirection based on unvalidated user input may cause redirection to malicious web sites.", output["rule"]["full_description"]
    end

    test "constructs hash for multiple code scanning alerts" do
      response = VCR.use_cassette("code-scanning/get-alerts-by-ref", persist_with: :turboscan) do
        GitHub::Turboscan.alerts(repository_id: @repo.id)
      end

      options = {
        repo: @repo,
      }
      output = serialize_hash_method(:code_scanning_alerts_hash, { alerts: response.data.results, total_count: response.data.total_count }, options)
      assert_equal output[3]["rule"]["tags"], %w[maintainability useless-code]

      unless @repo.code_scanning_alert_verbose_rules_enabled?
        assert_nil output[3]["rule"]["help"]
        assert_nil output[3]["rule"]["full_description"]
        assert_nil output[3]["repository"]
      end
    end

    test "constructs hash for multiple code scanning alerts for orgs" do
      # Create two repos to match the number of repos in the cassette
      repo_2 = create(:private_repository, owner: @org)
      repo_3 = create(:repository, owner: @org)

      response = VCR.use_cassette("code-scanning/org-alerts", persist_with: :turboscan) do
        GitHub::Turboscan.alerts_by_repo(owner_ids: [71])
      end

      repo_results = response&.data&.results || []

      # The cassette currently has 9 alerts but only two repo ids: 300 and 351, as defined in
      # turboscan/ts/cassettes/sessions/org_level_test.go. This ensures that we're getting what we're expecting
      # from the cassette, and therefore allows us to overwrite the response properly to match the repo ids
      # in the test fixtures.
      assert_same_elements [300, 351], repo_results.map(&:repository_id).uniq

      # We replace all results from the cassette so that the ids match those for the test fixtures and they are found
      # to be members of the org. The alternate approach of fixing the fixture repo ids causes flakiness due to id
      # clashes.
      repo_results.map do |repo_result|
        if repo_result.repository_id == 300
          repo_result.repository_id = repo_2.id
        elsif repo_result.repository_id == 351
          repo_result.repository_id = repo_3.id
        end
      end

      repo_ids = repo_results.map(&:repository_id).uniq
      repos_by_id = @org.repositories.where(id: repo_ids).index_by(&:id)

      output = serialize_hash_method(:org_code_scanning_alerts_hash, { repo_results: repo_results, repos_by_id: repos_by_id }, {})

      assert_equal output[0]["repository"]["id"], repo_2.id
      assert_equal output[0]["rule"]["tags"], []

      unless repo_2.code_scanning_alert_verbose_rules_enabled?
        assert_nil output[0]["rule"]["help"]
        assert_nil output[0]["rule"]["full_description"]
      end
    end

  end
end
