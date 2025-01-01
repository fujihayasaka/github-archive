# typed: true
# frozen_string_literal: true

require "test_helper"

class Organizations::Settings::SecurityProducts::RepositoriesControllerTest < GitHub::IntegrationTestCase
  include SecurityProductsEnablementHelpers
  include TurboghasHelpers
  include HydroMessageJobTestHelpers
  include SecurityProductsEnablement::EnterpriseTestHelpers

  setup do
    GitHub.flipper[:advanced_security_circuit_breaker].disable
    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
    @billable_entity.class.any_instance.stubs(:advanced_security_purchased?).returns(true)
  end

  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
    setup_search

    @random_user = create(:user, name: "random-user")
    @owner = create(:user, name: "org-owner")
    @org = create(:organization, admin: @owner)
    @billable_entity = AdvancedSecurityLicense.billable_entity(@org)
    @member = create(:user, name: "org-member")
    @org.add_member(@member)
    @security_manager = create(:user, name: "org-security-manager")
    @org.add_member(@security_manager)
    @security_manager_team = create(:security_manager_team, organization: @org)
    @security_manager_team.add_member(@security_manager)
    @repo1 = create(:repository, owner: @org)
    @repo2 = create(:repository, owner: @org)
    @repo3 = create(:private_repository, owner: @org)
    @repo4 = create(:archived_repository, owner: @org)

    if TestEnv.test_with_all_emus?
      @repo1.enable_vulnerability_alerts(actor: @owner)
      @repo2.enable_vulnerability_alerts(actor: @owner)
    end

    # Repositories are sorted by `recently_updated` scope
    # which sorts repos based on any update to the repo attributes
    @repo1.update!(pushed_at: 1.day.ago)
    @repo2.update!(pushed_at: nil)

    make_searchable(@repo1, @repo2, @repo3, @repo4)
  end

  teardown_once do
    teardown_search
  end

  context "#index" do
    test "returns serialized repositories" do
      security_config = create(:security_configuration, target: @org, name: "config1", description: "desc1")
      repo_config = RepositorySecurityConfiguration.create!(
        security_configuration_id: security_config.id,
        organization_id: @org.id,
        state: :attached,
        repository_id: @repo1.id
      )

      stub_licenses_required_result({
        @repo1.id => 0,
        @repo2.id => 0,
        @repo3.id => 1, # repo3 is the only private repository in the fixtures
      })

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products/repositories"

      assert_response :ok

      expected = {
        "repositories" => [
          {
            "id" => @repo3.id,
            "name" => @repo3.name,
            "visibility" => @repo3.visibility,
            "pushed_at" => @repo3.pushed_at.as_json,
            "licenses_required" => 1,
            "security_configuration" => nil,
            "security_features_enabled" => GitHub.enterprise? ? true : false, # The fixtures block enables DG for all repos in enterprise mode
          },
          {
            "id" => @repo1.id,
            "name" => @repo1.name,
            "visibility" => @repo1.visibility,
            "pushed_at" => @repo1.pushed_at.as_json,
            "licenses_required" => 0,
            "security_configuration" => {
              "name" => security_config.name,
              "status" => repo_config.state,
              "failure_reason" => repo_config.failure_reason,
              "is_github_recommended_configuration" => false,
              "repository_security_configuration_id" => repo_config.id
            },
            "security_features_enabled" => false,
          },
          {
            "id" => @repo2.id,
            "name" => @repo2.name,
            "visibility" => @repo2.visibility,
            "pushed_at" => @repo2.created_at.as_json,
            "licenses_required" => 0,
            "security_configuration" => nil,
            "security_features_enabled" => true,
          },
        ],
        "pageCount" => 1,
        "totalRepositoryCount" => 3,
        "searchResultsLimitExceeded" => false,
      }

      assert_equal expected, response.parsed_body
    end

    test "filters repositories when the search query is supported by Elasticsearch" do
      stub_licenses_required_result({
        @repo1.id => 0,
        @repo2.id => 0,
        @repo3.id => 1, # repo3 is the only private repository in the fixtures
      })

      # Repositories are sorted by `recently_updated` scope
      # which sorts repos based on any update to the repo attributes
      @repo1.update!(pushed_at: 4.days.ago)
      @repo3.update!(pushed_at: 1.day.ago)

      # Create custom properties so that we can test them in the query string
      definition_env = create :custom_property_definition,
        :single_select,
        source: @org,
        property_name: "environment",
        description: "prod test or dev",
        allowed_values: %w[prod test dev]
      [@repo1, @repo3].each do |repo|
        create :custom_property_value, definition: definition_env, target: repo, value: "prod"
        make_searchable(repo)
      end

      create :custom_property_value, definition: definition_env, target: @repo2, value: "dev"
      make_searchable(@repo2)

      # Filter repos
      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products/repositories",
        params: { q: "visibility:public,private,internal props.environment:prod sort:updated" }

      assert_response :ok

      expected = {
        "repositories" => [
          {
            "id" => @repo3.id,
            "name" => @repo3.name,
            "visibility" => @repo3.visibility,
            "pushed_at" => @repo3.pushed_at.as_json,
            "licenses_required" => 1,
            "security_configuration" => nil,
            "security_features_enabled" => GitHub.enterprise? ? true : false, # The fixtures block enables DG for all repos in enterprise mode
          },
          {
            "id" => @repo1.id,
            "name" => @repo1.name,
            "visibility" => @repo1.visibility,
            "pushed_at" => @repo1.pushed_at.as_json,
            "licenses_required" => 0,
            "security_configuration" => nil,
            "security_features_enabled" => true,
          }
        ],
        "pageCount" => 1,
        "totalRepositoryCount" => 2,
        "searchResultsLimitExceeded" => false
      }
      assert_equal expected, response.parsed_body
    end

    test "sets searchResultsLimitExceeded to true in the response when search results exceed the limit" do
      # Repositories are sorted by `recently_updated` scope
      # which sorts repos based on any update to the repo attributes
      @repo1.update!(pushed_at: 4.days.ago)
      @repo3.update!(pushed_at: 1.day.ago)
      make_searchable(@repo1, @repo3)

      stub_licenses_required_result({ @repo3.id => 1 })
      stub_const(SecurityProductsEnablement::ListReposQuery, :RESULTS_LIMIT, 1) do
        # Filter repos
        as @owner
        get "/organizations/#{@org.display_login}/settings/security_products/repositories",
          params: { q: "configuration:None sort:updated" }

        assert_response :ok
        expected = {
          "repositories" => [
            {
              "id" => @repo3.id,
              "name" => @repo3.name,
              "visibility" => @repo3.visibility,
              "pushed_at" => @repo3.pushed_at.as_json,
              "licenses_required" => 1,
              "security_configuration" => nil,
              "security_features_enabled" => GitHub.enterprise? ? true : false, # The fixtures block enables DG for all repos in enterprise mode
            },
          ],
          "pageCount" => 1,
          "totalRepositoryCount" => 1,
          "searchResultsLimitExceeded" => true,
        }
        assert_equal expected, response.parsed_body
      end
    end

    test "returns a successful response when there are no repositories" do
      owner = create(:user)
      org = create(:organization, admin: owner)

      as owner
      get "/organizations/#{org.display_login}/settings/security_products/repositories"

      assert_response :ok
      assert_equal({ "repositories" => [], "pageCount" => 1, "totalRepositoryCount" => 0, "searchResultsLimitExceeded" => false }, response.parsed_body)
    end

    test "allows security manager to view the list of repositories" do
      as @security_manager
      get "/organizations/#{@org.display_login}/settings/security_products/repositories"

      assert_response :ok
    end

    test "renders 404 for users who are not a memeber of the organization" do
      as @random_user
      get "/organizations/#{@org.display_login}/settings/security_products/repositories"

      assert_response :not_found
    end

    test "renders 404 for org members who don't have access" do
      as @member
      get "/organizations/#{@org.display_login}/settings/security_products/repositories"

      assert_response :not_found
    end
  end

  context "#advanced_security_license_summary" do
    test "returns license summary for given repositories in an entity" do
      AdvancedSecurityLicense.expects(:summary)
        .with(entity: @billable_entity, repository_ids: [@repo1.id, @repo2.id])
        .returns(Struct.new(:additional_committers, :unique_committers).new(20, 20))

      as @owner
      post "/organizations/#{@org.display_login}/settings/security_products/repositories/advanced_security_license_summary",
        params: { repository_ids: [@repo1.id, @repo2.id] }, as: :json

      assert_response :ok
    end

    test "returns license summary for entire entity if specific repositories or a query are not passed" do
      AdvancedSecurityLicense.expects(:summary)
        .with(entity: @billable_entity, repository_ids: nil)
        .returns(Struct.new(:additional_committers, :unique_committers).new(50, 60))

      as @owner
      post "/organizations/#{@org.display_login}/settings/security_products/repositories/advanced_security_license_summary"

      assert_response :ok
    end

    test "returns license summary for the repositories matching the query" do
      [@repo1, @repo2, @repo3].each { |repo| make_searchable(repo) }

      AdvancedSecurityLicense.expects(:summary)
        .with(entity: @billable_entity, repository_ids: [@repo3.id]) # Repo3 is private
        .returns(Struct.new(:additional_committers, :unique_committers).new(20, 20))

      as @owner
      post "/organizations/#{@org.display_login}/settings/security_products/repositories/advanced_security_license_summary",
        params: { repository_ids: [], query: "visibility:private", }, as: :json

      assert_response :ok
    end

    test "includes license overview in the response when requested" do
      AdvancedSecurityLicense.any_instance.stubs(
        allowance_exceeded?: false,
        unlimited_seats?: false,
        consumed_seats: 5,
        remaining_seats: 5,
        seats: 10,
      )
      AdvancedSecurityLicense.expects(:summary)
        .with(entity: @billable_entity, repository_ids: [@repo1.id, @repo2.id])
        .returns(Struct.new(:additional_committers, :unique_committers).new(5, 5))

      as @owner
      post "/organizations/#{@org.display_login}/settings/security_products/repositories/advanced_security_license_summary",
        params: { repository_ids: [@repo1.id, @repo2.id], include_license_overview: true }, as: :json

      expected_response = {
        "business" => GitHub.single_or_multi_tenant_enterprise? || TestEnv.test_with_all_emus? ? @billable_entity.name : nil,
        "consumedSeats" => 5,
        "remainingSeats" => 5,
        "allowanceExceeded" => false,
        "exceededSeats" => 0,
        "hasUnlimitedSeats" => false,
        "failedToFetchLicenses" => false,
        "licenses_needed" => 5,
        "licenses_freed" => 5
      }
      assert_equal expected_response, response.parsed_body
    end

    test "returns 422 when summary information is not available" do
      AdvancedSecurityLicense.expects(:summary).raises(AdvancedSecurityLicense::TurboghasError.new("Something bad happened!"))

      as @owner
      post "/organizations/#{@org.display_login}/settings/security_products/repositories/advanced_security_license_summary",
        params: { repository_ids: [@repo1.id, @repo2.id] }, as: :json

      assert_response :unprocessable_entity
    end
  end

  context "#apply_confirmation_summary" do
    test "it finds repositories by specified ids" do
      repository_ids = [@repo1.id, @repo2.id, @repo3.id]

      # Set the # of total and consumed seats for our entity:
      @billable_entity.class.any_instance.stubs(
        advanced_security_seats_for_entity: 100,
        advanced_security_seats_used: 10
      )

      stub_summary_result(
        billable_entity: @billable_entity,
        active_committers: 10,
        maximum_committers: 20,
        additional_committers: 10,
        repository_ids:
      )

      as @owner
      post "/organizations/#{@org.display_login}/settings/security_products/repositories/apply_confirmation_summary",
        params: { repository_ids:, enable_ghas: true }, as: :json

      expected_response = {
        "total_repo_count" => 3,
        "public_repo_count" => TestEnv.test_with_all_emus? ? 0 : 2, # Repos 1 and 2 are public
        "private_and_internal_repo_count" => TestEnv.test_with_all_emus? ? 3 : 1, # Repo 3 is private
        "private_and_internal_repos_count_exceeding_licenses" => 0,
        "licenses_needed" => 10,
        "errors" => []
      }

      assert_response :ok
      assert_equal expected_response, response.parsed_body
    end

    test "it finds all repositories when no IDs are specified" do
      # Set the # of total and consumed seats for our entity:
      @billable_entity.class.any_instance.stubs(
        advanced_security_seats_for_entity: 100,
        advanced_security_seats_used: 10
      )

      stub_summary_result(
        billable_entity: @billable_entity,
        active_committers: 10,
        maximum_committers: 20,
        additional_committers: 10,
        repository_ids: [@repo1.id, @repo2.id, @repo3.id]
      )

      as @owner
      post "/organizations/#{@org.display_login}/settings/security_products/repositories/apply_confirmation_summary",
        params: { repository_ids: [], enable_ghas: true }, as: :json

      expected_response = {
        "total_repo_count" => 3,
        "public_repo_count" => TestEnv.test_with_all_emus? ? 0 : 2, # Repos 1 and 2 are public
        "private_and_internal_repo_count" => TestEnv.test_with_all_emus? ? 3 : 1, # Repo 3 is private
        "private_and_internal_repos_count_exceeding_licenses" => 0,
        "licenses_needed" => 10,
        "errors" => []
      }

      assert_response :ok
      assert_equal expected_response, response.parsed_body
    end

    test "it finds repositories by a query parameter passed in" do
      repositories = [@repo1, @repo2, @repo3]

      # Set the # of total and consumed seats for our entity:
      @billable_entity.class.any_instance.stubs(
        advanced_security_seats_for_entity: 100,
        advanced_security_seats_used: 10
      )

      stub_summary_result(
        billable_entity: @billable_entity,
        active_committers: 10,
        maximum_committers: 20,
        additional_committers: 10,
        repository_ids: [@repo3.id]
      )

      repositories.each do |repo|
        make_searchable(repo)
      end

      as @owner
      post "/organizations/#{@org.display_login}/settings/security_products/repositories/apply_confirmation_summary",
        params: { query: "visibility:private", enable_ghas: true }, as: :json

      expected_response = {
        "total_repo_count" => 1,
        "public_repo_count" => 0,
        "private_and_internal_repo_count" => 1, # Repo 3 is private
        "private_and_internal_repos_count_exceeding_licenses" => 0,
        "licenses_needed" => 10,
        "errors" => []
      }

      assert_response :ok
      assert_equal expected_response, response.parsed_body
    end

    test "it finds only repositories with no configuration when option is specified" do
      security_config = create(:security_configuration, target: @org, name: "config1", description: "desc1")

      # Create attached security configurations for repos 1 and 2, so that they don't count as "no configuration":
      [@repo1.id, @repo2.id].each do |repo_id|
        RepositorySecurityConfiguration.create(
          repository_id: repo_id,
          organization_id: @org.id,
          security_configuration_id: security_config.id,
          state: :attached,
        )
      end

      # Set the # of total and consumed seats for our entity:
      @billable_entity.class.any_instance.stubs(
        advanced_security_seats_for_entity: 100,
        advanced_security_seats_used: 10
      )

      stub_summary_result(
        billable_entity: @billable_entity,
        active_committers: 10,
        maximum_committers: 20,
        additional_committers: 10,
        repository_ids: [@repo3.id] # Only specify repo3 since it doesn't have a configuration.
      )

      as @owner
      post "/organizations/#{@org.display_login}/settings/security_products/repositories/apply_confirmation_summary",
        params: { repository_ids: [], no_configuration_only: "true", enable_ghas: true }, as: :json

      expected_response = {
        "total_repo_count" => 1,
        "public_repo_count" => 0, # Repos 1 and 2 are public, but already have a config.
        "private_and_internal_repo_count" => 1, # Repo 3 is private
        "private_and_internal_repos_count_exceeding_licenses" => 0,
        "licenses_needed" => 10,
        "errors" => []
      }

      assert_response :ok
      assert_equal expected_response, response.parsed_body
    end

    test "returns 0 licenses needed when config does not enable GHAS" do
      @billable_entity.class.any_instance.stubs(
        advanced_security_seats_for_entity: 100,
        advanced_security_seats_used: 10
      )

      as @owner
      post "/organizations/#{@org.display_login}/settings/security_products/repositories/apply_confirmation_summary",
        params: { repository_ids: [], enable_ghas: false }, as: :json

      expected_response = {
        "total_repo_count" => 3,
        "public_repo_count" => TestEnv.test_with_all_emus? ? 0 : 2, # Repos 1 and 2 are public
        "private_and_internal_repo_count" => TestEnv.test_with_all_emus? ? 3 : 1, # Repo 3 is private
        "private_and_internal_repos_count_exceeding_licenses" => 0,
        "licenses_needed" => 0,
        "errors" => []
      }

      assert_response :ok
      assert_equal expected_response, response.parsed_body
    end

    test "returns an error when GHAS is not purchased for the organization" do
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)

      as @owner
      post "/organizations/#{@org.display_login}/settings/security_products/repositories/apply_confirmation_summary",
        params: { repository_ids: [], no_configuration_only: "true", enable_ghas: true }, as: :json
      assert_response :ok

      assert_equal({
        "total_repo_count" => 3,
        "public_repo_count" => TestEnv.test_with_all_emus? ? 0 : 2, # Repos 1 and 2 are public
        "private_and_internal_repo_count" => TestEnv.test_with_all_emus? ? 3 : 1, # Repo 3 is private
        "private_and_internal_repos_count_exceeding_licenses" => 0,
        "licenses_needed" => nil,
        "errors" => ["ghas_not_purchased"]
      }, response.parsed_body)
    end

    test "returns an error when the number of additional licenses exceeds the limit" do
      GitHub::Enterprise.license.stubs(advanced_security_seats: 1) if GitHub.enterprise?
      @billable_entity.class.any_instance.stubs(
        advanced_security_seats_for_entity: 1,
        advanced_security_seats_used: 1
      )
      stub_summary_result(
        billable_entity: @billable_entity,
        active_committers: 1,
        maximum_committers: 1,
        additional_committers: 2,
        repository_ids: [@repo3.id]
      )

      stub_licenses_required_result({
        @repo3.id => 2,
      })

      as @owner
      post "/organizations/#{@org.display_login}/settings/security_products/repositories/apply_confirmation_summary",
        params: { repository_ids: [@repo3.id], enable_ghas: true }, as: :json

      assert_response :ok
      assert_equal({
        "total_repo_count" => 1,
        "public_repo_count" => 0,
        "private_and_internal_repo_count" => 1,
        "private_and_internal_repos_count_exceeding_licenses" => 1,
        "licenses_needed" => 2,
        "errors" => ["license_limit_exceeded"]
      }, response.parsed_body)
    end

    test "returns an error when the number of additional licenses is 0 but the max number of licenses is already exceeded" do
      GitHub::Enterprise.license.stubs(advanced_security_seats: 1) if GitHub.enterprise?
      @billable_entity.class.any_instance.stubs(
        advanced_security_seats_for_entity: 1,
        advanced_security_seats_used: 9
      )
      stub_summary_result(
        billable_entity: @billable_entity,
        active_committers: 1,
        maximum_committers: 1,
        additional_committers: 0,
        repository_ids: [@repo3.id]
      )

      stub_licenses_required_result({
        @repo3.id => 0,
      })

      as @owner
      post "/organizations/#{@org.display_login}/settings/security_products/repositories/apply_confirmation_summary",
        params: { repository_ids: [@repo3.id], enable_ghas: true }, as: :json

      assert_response :ok
      assert_equal({
        "total_repo_count" => 1,
        "public_repo_count" => 0,
        "private_and_internal_repo_count" => 1,
        "private_and_internal_repos_count_exceeding_licenses" => 0,
        "licenses_needed" => 0,
        "errors" => ["license_limit_exceeded"]
      }, response.parsed_body)
    end

    test "does not return an error when the org already exceeds the license limit but only public repos are being selected", skip_in_multitenant_mode: true, skip_with_all_emus: true do
      @billable_entity.class.any_instance.stubs(
        advanced_security_seats_for_entity: 1,
        advanced_security_seats_used: 9
      )

      as @owner
      post "/organizations/#{@org.display_login}/settings/security_products/repositories/apply_confirmation_summary",
        params: { repository_ids: [@repo1.id, @repo2.id], enable_ghas: true }, as: :json

      assert_response :ok
      assert_equal({
        "total_repo_count" => 2,
        "public_repo_count" => 2,
        "private_and_internal_repo_count" => 0,
        "private_and_internal_repos_count_exceeding_licenses" => 0,
        "licenses_needed" => nil,
        "errors" => []
      }, response.parsed_body)
    end

    test "returns an error when GHAS changes are blocked by enterprise policy" do
      Organization.any_instance.stubs(:policy_allows_advanced_security_enablement?).returns(false)

      as @owner
      post "/organizations/#{@org.display_login}/settings/security_products/repositories/apply_confirmation_summary",
        params: { repository_ids: [@repo3.id], enable_ghas: true }, as: :json
      assert_response :ok

      assert_equal({
        "total_repo_count" => 1,
        "public_repo_count" => 0,
        "private_and_internal_repo_count" => 1,
        "private_and_internal_repos_count_exceeding_licenses" => 0,
        "licenses_needed" => nil,
        "errors" => ["blocked_by_enterprise_policy"]
      }, response.parsed_body)
    end
  end
end
