# typed: true
# frozen_string_literal: true

require "test_helper"
class Organizations::Settings::SecurityProductsControllerTest < GitHub::IntegrationTestCase
  include GitHub::ReactPayloadHelper
  include SecurityProductsEnablementHelpers
  include TurboghasHelpers
  include HydroMessageJobTestHelpers

  setup do
    GitHub.flipper[:security_configurations_talk_to_us_banner].enable

    if GitHub.enterprise?
      stub_security_products_manager(enabled: true)
    end
  end

  fixtures do
    @random_user = create(:user, name: "random-user")
    @owner = create(:user, name: "org-owner")
    @business = create(:global_business) || create(:business, owners: [@owner])
    @business.mark_advanced_security_as_purchased_for_entity(actor: @owner)
    @org = create(:organization, admin: @owner, business: @business)
    @member = create(:user, name: "org-member")
    @org.add_member(@member)
    @security_manager = create(:user, name: "org-security-manager")
    @org.add_member(@security_manager)
    @security_manager_team = create(:security_manager_team, organization: @org)
    @security_manager_team.add_member(@security_manager)
    @repo1 = create(:repository, owner: @org)
    @repo2 = create(:repository, owner: @org)
    @repo3 = create(:private_repository, owner: @org)
    @deleted_repository = create(:repository, :soft_deleted, owner: @org)
    if TestEnv.test_with_all_emus?
      @repo1.enable_vulnerability_alerts(actor: @owner)
      @repo2.enable_vulnerability_alerts(actor: @owner)
    end

    # Repositories are sorted by `recently_updated` scope
    # which sorts repos based on any update to the repo attributes
    @repo1.update!(pushed_at: 1.day.ago)
    @repo2.update!(pushed_at: 2.days.ago)

    make_searchable(@repo1, @repo2, @repo3)
  end

  context "#index" do
    test "renders 404 for users who are not a memeber of the organization" do
      as @random_user
      get "/organizations/#{@org.display_login}/settings/security_products"

      assert_response :not_found
    end

    test "renders 404 for org members who don't have access" do
      as @member
      get "/organizations/#{@org.display_login}/settings/security_products"

      assert_response :not_found
    end

    test "renders for security managers" do
      as @security_manager
      get "/organizations/#{@org.display_login}/settings/security_products"

      assert_response :success
    end

    test "renders for an org admin" do
      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products"

      assert_response :success
    end

    test "payload includes default values and organization name and empty set of configs" do
      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products"

      ghr_payload = unless GitHub.enterprise?
        {
          "id" => SecurityConfiguration.github_recommended_configuration&.id,
          "name" => SecurityConfiguration.github_recommended_configuration&.name,
          "description" => SecurityConfiguration.github_recommended_configuration&.description,
          "default_for_new_public_repos" => false,
          "default_for_new_private_repos" => false,
          "enforcement" => "not_enforced",
          "enable_ghas" => true,
          "repositories_count" => 0
        }
      end

      assert_react_payload_equal :organization, @org.display_login

      if GitHub.enterprise?
        assert_react_payload_nil(:githubRecommendedConfiguration)
      else
        assert_react_payload_equal :githubRecommendedConfiguration, ghr_payload
      end

      assert_react_payload_equal :customSecurityConfigurations, []

      assert_react_payload_equal :customEnterpriseSecurityConfigurations, []

      assert_react_payload_equal :capabilities, {
        "actionsAreBilled" => !GitHub.enterprise?,
        "ghasFreeForPublicRepos" => !GitHub.enterprise?,
        "hasPublicRepos" => !TestEnv.test_in_multitenancy_mode?,
        "previewNext" => GitHub.flipper[:security_configurations_preview_next].enabled?,
        "enterpriseOwned" => true,
        "ghasPurchased" => true,
        "hasTeams" => true,
      }

      assert_react_payload_equal :securityProducts, {
        "dependency_graph" => {
          "availability" => "available",
          "configurablePerRepo" => !GitHub.enterprise?
        },
        "dependency_graph_autosubmit_action" => {
          "availability" => GitHub.enterprise? ? "unavailable" : "available"
        },
        "dependabot_alerts" => {
          "availability" => "available"
        },
        "dependabot_vea" => {
          "availability" => "available"
        },
        "dependabot_updates" => {
          "availability" => "available"
        },
        "code_scanning" => {
          "availability" => "available", "onlyLabeledRunners" => GitHub.enterprise?, "runnerLabels" => [],
        },
        "secret_scanning" => {
          "availability" => "available"
        },
        "private_vulnerability_reporting" => {
          "availability" => TestEnv.test_in_multitenancy_mode? || GitHub.enterprise? ? "unavailable" : "available"
        },
      }

      assert get_react_payload_value_from_keys(%w[docsUrls createConfig]).start_with?("https://docs.github.com")
      assert get_react_payload_value_from_keys(%w[docsUrls ghasBilling]).start_with?("https://docs.github.com")
      assert get_react_payload_value_from_keys(%w[docsUrls ghasTrial]).start_with?("https://docs.github.com")
      assert get_react_payload_value_from_keys(%w[docsUrls installSecurityProducts]).start_with?("https://docs.github.com")

      if TestEnv.enterprise?
        assert_nil get_react_payload_value_from_keys(%w[docsUrls userOwnedRepos])
      else
        assert get_react_payload_value_from_keys(%w[docsUrls userOwnedRepos]).start_with?("https://docs.github.com")
      end
    end

    test "payload includes correct availability status when security products are unavailable" do
      stub_security_products_manager enabled: false

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products"

      assert_react_payload_equal :organization, @org.display_login

      assert_react_payload_equal :securityProducts, {
        "dependency_graph" => {
          "availability" => "unavailable",
          "configurablePerRepo" => !GitHub.enterprise?
        },
        "dependency_graph_autosubmit_action" => {
          "availability" => GitHub.enterprise? ? "unavailable" : "available"
        },
        "dependabot_alerts" => {
          "availability" => "unavailable"
        },
        "dependabot_vea" => {
          "availability" => "unavailable"
        },
        "dependabot_updates" => {
          "availability" => "unavailable"
        },
        "code_scanning" => {
          "availability" => "unavailable", "onlyLabeledRunners" => GitHub.enterprise?, "runnerLabels" => [],
        },
        "secret_scanning" => {
          "availability" => "unavailable"
        },
        "private_vulnerability_reporting" => {
          "availability" => "unavailable"
        },
      }
    end

    test "payload includes organization name and repository count for GH config", skip_enterprise: true do
      repo_config = RepositorySecurityConfiguration.create!(
        security_configuration_id: T.must(SecurityConfiguration.github_recommended_configuration).id,
        state: :attached,
        organization: @org,
        repository_id: @repo1.id
      )

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products"

      assert_react_payload_equal :organization, @org.display_login
      assert_react_payload_equal :githubRecommendedConfiguration, {
        "id" => T.must(SecurityConfiguration.github_recommended_configuration).id,
        "name" => T.must(SecurityConfiguration.github_recommended_configuration).name,
        "description" => T.must(SecurityConfiguration.github_recommended_configuration).description,
        "default_for_new_public_repos" => false,
        "default_for_new_private_repos" => false,
        "enforcement" => "not_enforced",
        "enable_ghas" => true,
        "repositories_count" => 1
      }
      assert_react_payload_equal :customSecurityConfigurations, []
    end

    test "payload includes configurations when present" do
      config = create(:security_configuration, :default_for_new_private_repos, target: @org, name: "config1", description: "desc1")

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products"

      assert_react_payload_equal :organization, @org.display_login
      assert_react_payload_equal :custom_security_configurations, [{
        "id" => config.id,
        "name" => "config1",
        "description" => "desc1",
        "enable_ghas" => true,
        "repositories_count" => 0,
        "default_for_new_public_repos" => false,
        "default_for_new_private_repos" => true,
        "enforcement" => "not_enforced",
      }]
    end

    test "payload includes custom property suggestions" do
      create(
        :custom_property_definition,
        :single_select,
        source: @org,
        property_name: "environment",
        description: "prod test or dev",
        allowed_values: %w[prod test dev]
      )

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products"

      assert_react_payload_equal :custom_property_suggestions, [{
        "propertyName" => "environment",
        "valueType" => "single_select",
        "required" => false,
        "defaultValue" => nil,
        "description" => "prod test or dev",
        "allowedValues" => %w[prod test dev],
        "valuesEditableBy" => "org_actors",
        "regex" => nil,
        "sourceType" => "org",
        "source" => {
          "type" => "org",
          "name" => @org.safe_profile_name,
          "slug" => @org.display_login,
          "avatarUrl" => @org.primary_avatar_url(60)
        }
      }]
    end

    test "payload includes total repository count" do
      stub_const(Settings::SecurityProducts::RepositoriesHelper, :DEFAULT_PER_PAGE, 2) do
        as @owner
        get "/organizations/#{@org.display_login}/settings/security_products"
      end

      assert_react_payload_equal :totalRepositoryCount, 3
      assert_react_payload_equal :page_count, 2
      assert_react_payload_count :repositories, 2
    end

    test "payload includes repositories" do
      security_config = create(:security_configuration, target: @org, name: "config1", description: "desc1")

      repo_config = RepositorySecurityConfiguration.create!(
        security_configuration_id: security_config.id,
        state: :attaching,
        organization_id: @org.id,
        repository_id: @repo1.id
      )

      SecurityProductsEnablement::JobProgressTracker.new(@org.id).start

      stub_licenses_required_result({
        @repo1.id => 0,
        @repo2.id => 0,
        @repo3.id => 1, # repo3 is the only private repository in the fixtures
      })

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products"

      assert_react_payload_equal :repositories, [
        {
          "id" => @repo3.id,
          "name" => @repo3.name,
          "visibility" => @repo3.visibility,
          "archived" => @repo3.archived?,
          "pushed_at" => @repo3.pushed_at.as_json,
          "licenses_required" => 1,
          "security_configuration" => nil,
          "security_features_enabled" => false,
        },
        {
          "id" => @repo1.id,
          "name" => @repo1.name,
          "visibility" => @repo1.visibility,
          "archived" => @repo1.archived?,
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
          "archived" => @repo2.archived?,
          "pushed_at" => @repo2.pushed_at.as_json,
          "licenses_required" => 0,
          "security_configuration" => nil,
          "security_features_enabled" => GitHub.enterprise? ? false : true, # dependency graph is not automatically enabled on enterprise
        },
      ]
    end

    test "payload returns second page of results" do
      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products", params: { page: "2" }

      # the second page is empty because we only have 3 repos
      assert_react_payload_equal :repositories, []
    end

    test "payload will filter repositories by query string" do
      stub_licenses_required_result({
        @repo3.id => 1, # repo3 is the only private repository in the fixtures
      })

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products", params: { q: "visibility:private" }

      assert_react_payload_equal :repositories, [
        {
          "id" => @repo3.id,
          "name" => @repo3.name,
          "visibility" => "private",
          "archived" => @repo3.archived?,
          "pushed_at" => @repo3.pushed_at.as_json,
          "licenses_required" => 1,
          "security_configuration" => nil,
          "security_features_enabled" => false,
        }
      ]
    end

    test "payload includes GitHub Advanced Security license information when purchased" do
      AdvancedSecurityLicense.any_instance.stubs(
        allowance_exceeded?: false,
        unlimited_seats?: false,
        consumed_seats: 5,
        remaining_seats: 5,
        seats: 0,
      )

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products"

      assert_react_payload_equal :licenses, {
        "allowanceExceeded" => false,
        "remainingSeats" => 5,
        "consumedSeats" => 5,
        "exceededSeats" => 0,
        "hasUnlimitedSeats" => false,
        "business" => @business.name,
        "failedToFetchLicenses" => false
      }
    end

    test "payload includes default GitHub Advanced Security license information when org hasn't purchased it" do
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)
      Organization.any_instance.expects(:advanced_securtiy_license).never

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products"

      assert_react_payload_equal :licenses, {
        "allowanceExceeded" => false,
        "remainingSeats" => 0,
        "consumedSeats" => 0,
        "exceededSeats" => 0,
        "hasUnlimitedSeats" => false,
        "business" => nil,
        "failedToFetchLicenses" => false
      }
    end

    test "payload indicates that license information could not be fetched" do
      AdvancedSecurityLicense.expects(:summary).raises(AdvancedSecurityLicense::TurboghasError.new("Something bad happened!"))

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products"

      assert_react_payload_equal :licenses, {
        "allowanceExceeded" => false,
        "remainingSeats" => 0,
        "consumedSeats" => 0,
        "exceededSeats" => 0,
        "hasUnlimitedSeats" => false,
        "business" => nil,
        "failedToFetchLicenses" => true
      }
    end

    test "we don't display the info banner on a GHAS org" do
      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products"

      assert @org.advanced_security_purchased?
      assert_react_payload_equal :showInfoBanner, false
    end

    test "we don't display the info banner on a non-GHAS GHES org", enterprise_only: true do
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products"

      assert_react_payload_equal :showInfoBanner, false
    end

    test "we show the info banner on a non-GHAS dotcom org", skip_enterprise: true do
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products"

      assert_react_payload_equal :showInfoBanner, true
    end

    test "we don't show the banner if the user has dismissed it", skip_enterprise: true do
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)

      @owner.dismiss_notice(UserNotice::SECURITY_CONFIGURATIONS_NON_GHAS_ORG_INFO_NOTICE)

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products"

      assert_react_payload_equal :showInfoBanner, false
    end

    test "we don't show the talk to us banner if we are showing the info banner", skip_enterprise: true do
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products"

      assert_react_payload_equal :showInfoBanner, true
      assert_react_payload_equal :showTalkToUsBanner, false
    end

    test "we don't show the talk to us banner if the user has dismissed it" do
      @owner.dismiss_notice(UserNotice::SECURITY_CONFIGURATIONS_TALK_TO_US_NOTICE)

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products"

      assert_react_payload_equal :showTalkToUsBanner, false
    end

    test "we show the talk to us banner" do
      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products"

      assert_react_payload_equal :showTalkToUsBanner, true
    end

    test "payload indicates if enablement changes are in progress" do
      Organization.any_instance.expects(:security_configurations_blocked?).returns(true)

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products"

      assert_react_payload_equal :changesInProgress, { "inProgress" => true, "type" => "enablement_changes" }
    end

    test "payload indicates if applying configurations are in progress" do
      Organization.any_instance.expects(:jobs_in_progress?).returns(true)

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products"

      assert_react_payload_equal :changesInProgress, { "inProgress" => true, "type" => "applying_configuration" }
    end
  end

  context "in_progress" do
    test "returns correct changes if security configurations are blocked" do
      Organization.any_instance.expects(:security_configurations_blocked?).returns(true)

      as @owner
      post "/organizations/#{@org.display_login}/settings/security_products/in_progress"

      assert_response :success
      expected_response = { inProgress: true, type: "enablement_changes" }
      assert_equal expected_response.to_json, response.body
    end

    test "returns correct changes if a config is being applied" do
      Organization.any_instance.expects(:jobs_in_progress?).returns(true)

      as @owner
      post "/organizations/#{@org.display_login}/settings/security_products/in_progress"

      assert_response :success
      expected_response = { inProgress: true, type: "applying_configuration" }
      assert_equal expected_response.to_json, response.body
    end

    test "returns false if no security configurations are applying or blocked" do
      Organization.any_instance.expects(:security_configurations_blocked?).returns(false)
      Organization.any_instance.expects(:jobs_in_progress?).returns(false)

      as @owner
      post "/organizations/#{@org.display_login}/settings/security_products/in_progress"

      assert_response :success
      expected_response = { inProgress: false }
      assert_equal expected_response.to_json, response.body
    end

    test "returns repositoryStatuses if repository_ids are passed" do
      security_config = create(:security_configuration, target: @org)
      [[@repo1, :attaching], [@repo2, :attached]].each do |repo, state|
        RepositorySecurityConfiguration.create!(
          security_configuration_id: security_config.id,
          organization: @org,
          state:,
          repository_id: repo.id
        )
      end

      Organization.any_instance.expects(:security_configurations_blocked?).returns(true)

      as @owner
      post "/organizations/#{@org.display_login}/settings/security_products/in_progress",
        params: { repository_ids: [@repo1.id, @repo2.id] }, as: :json

      assert_response :success

      expected_response = {
        "inProgress" => true,
        "type" => "enablement_changes",
        "repositoryStatuses" => {
          @repo1.id.to_s => {
            "name" => security_config.name,
            "status" => "attaching",
          },
          @repo2.id.to_s => {
            "name" => security_config.name,
            "status" => "attached",
          }
        }
      }

      assert_equal expected_response, JSON.parse(response.body)
    end

    test "does not return repositoryStatuses if repository_ids are not passed" do
      security_configuration = create(:security_configuration, target: @org)
      [[@repo1, :attaching], [@repo2, :attached]].each do |repo, state|
        RepositorySecurityConfiguration.create!(
          security_configuration_id: security_configuration.id,
          organization: @org,
          state:,
          repository_id: repo.id
        )
      end

      Organization.any_instance.expects(:security_configurations_blocked?).returns(false)
      Organization.any_instance.expects(:jobs_in_progress?).returns(false)

      as @owner
      post "/organizations/#{@org.display_login}/settings/security_products/in_progress"

      assert_response :success

      expected_response = { "inProgress" => false }
      assert_equal expected_response.to_json, response.body
    end
  end

  context "#refresh" do
    test "returns the serialized GitHub recommended configuration and custom security configurations for org and enterprise" do
      GitHub.flipper[:enterprise_security_configurations].enable
      github_recommended_configuration = SecurityConfiguration.github_recommended_configuration
      expected_github_recommended_configuration = unless GitHub.enterprise?
        {
          "id" => T.must(github_recommended_configuration).id,
          "name" => T.must(github_recommended_configuration).name,
          "description" => T.must(github_recommended_configuration).description,
          "default_for_new_public_repos" => false,
          "default_for_new_private_repos" => false,
          "enforcement" => "not_enforced",
          "enable_ghas" => true,
          "repositories_count" => 0
        }
      end

      config = create(:security_configuration, target: @org)
      expected_custom_security_configuration = {
        "id" => config.id,
        "name" => config.name,
        "description" => config.description,
        "default_for_new_public_repos" => false,
        "default_for_new_private_repos" => false,
        "enforcement" => "not_enforced",
        "enable_ghas" => true,
        "repositories_count" => 0
      }

      enterprise_config = create(:security_configuration, target: @business)
      expected_custom_enterprise_security_configuration = {
        "id" => enterprise_config.id,
        "name" => enterprise_config.name,
        "description" => enterprise_config.description,
        "default_for_new_public_repos" => false,
        "default_for_new_private_repos" => false,
        "enforcement" => "not_enforced",
        "enable_ghas" => true,
        "repositories_count" => 0
      }

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products/refresh"

      expected_response = {
        githubRecommendedConfiguration: expected_github_recommended_configuration,
        customSecurityConfigurations: [expected_custom_security_configuration],
        customEnterpriseSecurityConfigurations: [expected_custom_enterprise_security_configuration],
        failureCounts: {},
        licenses: {
          allowanceExceeded: false,
          remainingSeats: 0,
          consumedSeats: 0,
          exceededSeats: 0,
          hasUnlimitedSeats: true,
          business: @business.name,
          failedToFetchLicenses: false
        },
        inProgress: false,
      }

      assert_response :success
      assert_equal expected_response.to_json, response.body
    end

    # This test can be removed when we remove the feature flag.
    # We are skipping enterprise since ELC is always enabled on enterprise
    test "returns the serialized GitHub recommended configuration and org custom security configurations when enterprise flag is disabled", skip_enterprise: true do
      GitHub.flipper[:enterprise_security_configurations].disable
      github_recommended_configuration = SecurityConfiguration.github_recommended_configuration
      expected_github_recommended_configuration = unless GitHub.enterprise?
        {
          "id" => T.must(github_recommended_configuration).id,
          "name" => T.must(github_recommended_configuration).name,
          "description" => T.must(github_recommended_configuration).description,
          "default_for_new_public_repos" => false,
          "default_for_new_private_repos" => false,
          "enforcement" => "not_enforced",
          "enable_ghas" => true,
          "repositories_count" => 0
        }
      end

      config = create(:security_configuration, target: @org)
      expected_custom_security_configuration = {
        "id" => config.id,
        "name" => config.name,
        "description" => config.description,
        "default_for_new_public_repos" => false,
        "default_for_new_private_repos" => false,
        "enforcement" => "not_enforced",
        "enable_ghas" => true,
        "repositories_count" => 0
      }

      enterprise_config = create(:security_configuration, target: @business)
      expected_custom_enterprise_security_configuration = {
        "id" => enterprise_config.id,
        "name" => enterprise_config.name,
        "description" => enterprise_config.description,
        "default_for_new_public_repos" => false,
        "default_for_new_private_repos" => false,
        "enforcement" => "not_enforced",
        "enable_ghas" => true,
        "repositories_count" => 0
      }

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products/refresh"

      expected_response = {
        githubRecommendedConfiguration: expected_github_recommended_configuration,
        customSecurityConfigurations: [expected_custom_security_configuration],
        customEnterpriseSecurityConfigurations: [],
        failureCounts: {},
        licenses: {
          allowanceExceeded: false,
          remainingSeats: 0,
          consumedSeats: 0,
          exceededSeats: 0,
          hasUnlimitedSeats: true,
          business: @business.name,
          failedToFetchLicenses: false
        },
        inProgress: false,
      }

      assert_response :success
      assert_equal expected_response.to_json, response.body
    end

    test "returns repositories if repository_ids are passed" do
      github_config = SecurityConfiguration.github_recommended_configuration
      config = create(:security_configuration, target: @org)

      stub_licenses_required_result({
        @repo1.id => 0,
        @repo2.id => 0,
        @repo3.id => 1, # repo3 is the only private repository in the fixtures
      })

      [[@repo1, :attaching], [@repo2, :attached], [@repo3, :failed]].each do |repo, state|
        RepositorySecurityConfiguration.create!(
          organization: @org,
          security_configuration_id: T.must(config).id,
          state:,
          repository_id: repo.id,
          failure_reason: (state == :failed ? "Advanced security has not been purchased." : nil)
        )
      end

      repo_configs = RepositorySecurityConfiguration.where(repository_id: [@repo1.id, @repo2.id, @repo3.id])

      Organization.any_instance.expects(:security_configurations_blocked?).returns(true)

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products/refresh",
        params: { repository_ids: [@repo1.id, @repo2.id, @repo3.id] }
      assert_response :success

      expected_github_recommended_configuration = unless GitHub.enterprise?
        {
          "id" => github_config&.id,
          "name" => github_config&.name,
          "description" => github_config&.description,
          "default_for_new_public_repos" => false,
          "default_for_new_private_repos" => false,
          "enforcement" => "not_enforced",
          "enable_ghas" => true,
          "repositories_count" => 0
        }
      end

      expected_custom_security_configuration = {
        "id" => config.id,
        "name" => config.name,
        "description" => config.description,
        "default_for_new_public_repos" => false,
        "default_for_new_private_repos" => false,
        "enforcement" => "not_enforced",
        "enable_ghas" => true,
        "repositories_count" => 1
      }

      expected_response = {
        "githubRecommendedConfiguration" => expected_github_recommended_configuration,
        "customSecurityConfigurations" => [expected_custom_security_configuration],
        "customEnterpriseSecurityConfigurations" => [],
        "failureCounts" => {
          "GitHub Advanced Security has not been purchased" => 1
        },
        "licenses" => {
          "allowanceExceeded" => false,
          "remainingSeats" => 0,
          "consumedSeats" => 0,
          "exceededSeats" => 0,
          "hasUnlimitedSeats" => true,
          "business" => @business.name,
          "failedToFetchLicenses" => false,
        },
        "inProgress" => true,
        "type" => "enablement_changes",
        "totalRepositoryCount" => 3,
        "repositories" => [
          {
            "id" => @repo3.id,
            "name" => @repo3.name,
            "visibility" => @repo3.visibility,
            "archived" => @repo3.archived?,
            "pushed_at" => @repo3.pushed_at.as_json,
            "licenses_required" => 1,
            "security_configuration" => {
              "name" => T.must(config).name,
              "status" => "failed",
              "failure_reason" => "Advanced security has not been purchased.",
              "is_github_recommended_configuration" => false,
              "repository_security_configuration_id" => repo_configs.find_by(repository_id: @repo3.id)&.id,
            },
            "security_features_enabled" => false # adjust as necessary
          },
          {
            "id" => @repo1.id,
            "name" => @repo1.name,
            "visibility" => @repo1.visibility,
            "archived" => @repo1.archived?,
            "pushed_at" => @repo1.pushed_at.as_json,
            "licenses_required" => 0,
            "security_configuration" => {
              "name" => T.must(config).name,
              "status" => "attaching",
              "failure_reason" => nil,
              "is_github_recommended_configuration" => false,
              "repository_security_configuration_id" => repo_configs.find_by(repository_id: @repo1.id)&.id,
            },
            "security_features_enabled" => false
          },
          {
            "id" => @repo2.id,
            "name" => @repo2.name,
            "visibility" => @repo2.visibility,
            "archived" => @repo2.archived?,
            "pushed_at" => @repo2.pushed_at.as_json,
            "licenses_required" => 0,
            "security_configuration" => {
              "name" => T.must(config).name,
              "status" => "attached",
              "failure_reason" => nil,
              "is_github_recommended_configuration" => false,
              "repository_security_configuration_id" => repo_configs.find_by(repository_id: @repo2.id)&.id,
            },
            "security_features_enabled" => false
          }
        ],
      }

      assert_equal expected_response, JSON.parse(response.body)
    end

    test "returns failureCounts (includes archived repos) if the organization has failed configs" do
      repo_config_1 = create(:repository_security_configuration, organization: @org, repository: @repo1, state: :failed, failure_reason: nil)
      repo_config_2 = create(:repository_security_configuration, organization: @org, repository: @repo2, state: :failed, failure_reason: "Actions lol")
      repo_config_3 = create(:repository_security_configuration, organization: @org, repository: @repo3, state: :failed, failure_reason: "Advanced security has not been purchased.")

      archived_repository = create(:archived_repository, owner: @org)
      repo_config_4 = create(:repository_security_configuration, organization: @org, repository: archived_repository, state: :failed, failure_reason: nil)

      as @owner
      get "/organizations/#{@org.display_login}/settings/security_products/refresh"
      assert_response :success

      expected_failure_counts = {
        "of an unknown reason" => 3,
        "GitHub Advanced Security has not been purchased" => 1
      }
      parsed_response = JSON.parse(response.body)
      assert_equal expected_failure_counts, parsed_response["failureCounts"]
    end
  end

  context "#dismiss_failure_banner" do
    test "does nothing if there are no failures" do
      assert RepositorySecurityConfiguration.where(state: :failed).delete_all

      as @owner
      post "/organizations/#{@org.display_login}/settings/security_products/dismiss_failure_banner"
      assert_response :no_content
    end

    test "caches the latest failure timestamp" do
      kv_key = "failure_banner_dismissed_for:#{@owner.id}:#{@org.id}"
      assert_nil SecurityProductsEnablement::KV.get(kv_key).value!

      failed_attachment = create(:repository_security_configuration, organization: @org, state: :failed)

      as @owner
      post "/organizations/#{@org.display_login}/settings/security_products/dismiss_failure_banner"
      assert_response :created

      expected_timestamp = failed_attachment.updated_at.to_i.to_s
      assert expected_timestamp, SecurityProductsEnablement::KV.get(kv_key).value!
    end

    test "updates an existing cached value" do
      kv_key = "failure_banner_dismissed_for:#{@owner.id}:#{@org.id}"

      first_failure = create(:repository_security_configuration, organization: @org, state: :failed)
      SecurityProductsEnablement::KV.set(kv_key, first_failure.updated_at.to_i.to_s)

      # Now let's create a second failure:
      second_failure = create(:repository_security_configuration, organization: @org, state: :failed)

      # Ensure they don't have the same updated_at value, else this test fails:
      refute_equal first_failure.updated_at, second_failure.updated_at

      as @owner
      post "/organizations/#{@org.display_login}/settings/security_products/dismiss_failure_banner"
      assert_response :created

      expected_timestamp = second_failure.updated_at.to_i.to_s
      assert expected_timestamp, SecurityProductsEnablement::KV.get(kv_key).value!
    end
  end

  def stub_security_products_manager(enabled: true)
    SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(:dependency_graph_enabled?).returns(enabled)
    SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(:dependabot_alerts_enabled?).returns(enabled)
    SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(:dependabot_security_updates_enabled?).returns(enabled)
    SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(:dependabot_vea_enabled?).returns(enabled)
    SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(:code_scanning_default_setup_enabled?).returns(enabled)
    SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(:secret_scanning_enabled?).returns(enabled)
    # PVR is not in GHES
    SecurityProductsEnablement::SecurityProductsManager.any_instance.stubs(:private_vulnerability_reporting_enabled?).returns(enabled) unless GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
  end
end
