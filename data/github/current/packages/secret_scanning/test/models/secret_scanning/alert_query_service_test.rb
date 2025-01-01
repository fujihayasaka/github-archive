# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning
  class SecretScanningAlertQueryServiceTest < GitHub::TestCase
    include DogstatsTestHelpers

    ResponseMock = Struct.new(:data, :error)
    ResponseDataMock = Struct.new(:unresolved_count)

    fixtures do
      @user = create(:paid_user)
      @user_session = create(:user_session, user: @user)
      @business = create(:global_business)
      @business.add_owner(@user, actor: nil)

      @org1 = create(:business_plus_organization, business: @business, login: "Org1", admin: @user)
      @org2 = create(:business_plus_organization, business: @business, login: "Org2", admin: @user)
      @org3 = create(:business_plus_organization, business: @business, login: "Org3", admin: @user)

      @topica = create(:topic, name: "topica")
      @topicb = create(:topic, name: "topicb")
      @topicc = create(:topic, name: "topicc")

      @repo1a = create(:repository, owner: @org1, name: "repo1a").tap do |r|
        create(:repository_security_center_config, repository: r)
        create(:repository_topic, topic: @topica, state: :created, repository: r)
      end
      @repo1b = create(:repository, owner: @org1, name: "repo1b").tap do |r|
        create(:repository_security_center_config, repository: r)
        create(:repository_topic, topic: @topicb, state: :created, repository: r)
      end
      @repo1c = create(:repository, owner: @org1, name: "repo1c").tap do |r|
        create(:repository_security_center_config, repository: r)
        create(:repository_topic, topic: @topicc, state: :created, repository: r)
      end

      @team1a = create(:secret_team, organization: @org1).tap { |t| t.add_repository(@repo1a, :admin) }
      @team1b = create(:public_team, organization: @org1).tap { |t| t.add_repository(@repo1b, :admin) }
      @team1c = create(:public_team, organization: @org1).tap { |t| t.add_repository(@repo1c, :admin) }

      if !GitHub.enterprise?
        @other_business = create(:business, force_new_enterprise: true)
        @other_business_org = create(:organization, business: @other_business)
        @other_business_org_repo = create(:repository, owner: @other_business_org).tap do |r|
          create(:repository_security_center_config, repository: r)
          create(:repository_topic, topic: @topica, state: :created, repository: r)
          create(:repository_topic, topic: @topicb, state: :created, repository: r)
          create(:repository_topic, topic: @topicc, state: :created, repository: r)
        end
      end

      # Fixtures for testing business selector against EMU repositories
      if !GitHub.enterprise?
        @emu_biz = create(:business, :enterprise_managed, name: "enterprise-managed-business")
        @emu_owner = @emu_biz.find_first_emu_owner

        # create a few orgs in the business
        @emu_org1 = create(:organization, business: @emu_biz, admin: @emu_owner)
        @emu_org2 = create(:organization, business: @emu_biz, admin: @emu_owner)
        @emu_org3 = create(:organization, business: @emu_biz, admin: @emu_owner)

        # create a few emu accounts
        @emu_user1 = create(:emu, business: @emu_biz)
        @emu_user2 = create(:emu, business: @emu_biz)
        @emu_user3 = create(:emu, business: @emu_biz)

        [@emu_org1, @emu_org2, @emu_org3].each do |owner|
          r = create(:repository, owner: owner)

          # TODO: Cannot do this yet, which means the `repo` filter does not work with nwos from EMU accounts
          # See usage of `RepositorySecurityCenterConfig` in `BusinessScopeStrategy#filtered_repo_ids`
          # create(:repository_security_center_config, repository: r)
        end

        @emu_repo1 = create(:repository, owner: @emu_user1, force_user_owned: true)
        @emu_repo2 = create(:repository, owner: @emu_user2, force_user_owned: true)
        @emu_repo3 = create(:repository, owner: @emu_user3, force_user_owned: true)
      end
      perform_enqueued_jobs only: BusinessUserAccountUpdateAttributesJob

      enterprise_security_manager_team = create :enterprise_security_manager_team, business: @business
      @enterprise_security_manager = create :user
      @org1.add_member @enterprise_security_manager # Because the factory doesn't set up the org teams sync
      enterprise_security_manager_team.bulk_add_members(users: [@enterprise_security_manager])
      @esm_session = create(:user_session, user: @enterprise_security_manager)
    end

    setup do
      Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
    end

    context "#for_business" do
      test "creates instance" do
        result = AlertQueryService.for_business(business: @business, organizations: @business.organizations, current_user: @user, user_session: @user_session)
        assert result.instance_of? AlertQueryService
        assert result.strategy.instance_of? AlertQueryService::BusinessScopeStrategy
      end
    end

    context "#for_organization" do
      test "creates instance" do
        result = AlertQueryService.for_organization(organization: @org1, current_user: @user, user_session: @user_session)
        assert result.instance_of? AlertQueryService
        assert result.strategy.instance_of? AlertQueryService::OrganizationScopeStrategy
      end
    end

    context "#for_repository" do
      test "creates instance" do
        result = AlertQueryService.for_repository(repository: @repo1a, current_user: @user)
        assert result.instance_of? AlertQueryService
        assert result.strategy.instance_of? AlertQueryService::RepositoryScopeStrategy
      end
    end

    context ".generic_results_alert_count" do
      test "for business" do
        query = Search::Queries::SecurityCenter::SecretScanningQuery::default_query_generic_results
        SecretScanning::Features::Business::LowerConfidencePatterns.any_instance.stubs(:feature_available?).returns(true)
        feature_flags = T.let(["stop_using_has_valid_locations"], T::Array[T.any(String, Symbol)])
        if GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GENERIC_SECRETS_BLOCK].enabled?
          feature_flags << :secret_scanning_generic_secrets_block
        end
        expected_unresolved_count = 15
        expected_user_filter = GitHub.enterprise? || TestEnv.test_with_all_emus? ? :ALL : :NONE
        GitHub::TokenScanning::Service::Client
          .any_instance
          .stubs(:get_token_counts)
          .with(has_entries(
            {
              low_confidence: true,
              business_selector: GitHub::Proto::SecretScanning::Api::V2::BusinessSelector.new(
                id: @business.id,
                organization_ids: @business.organizations.map(&:id),
                repository_ids: [],
                repository_visibilities: [:REPOSITORY_VISIBILITY_PUBLIC, :REPOSITORY_VISIBILITY_PRIVATE, :REPOSITORY_VISIBILITY_INTERNAL],
                repos_are_excluded: false,
                user_ids: [],
                user_filter: expected_user_filter,
              ),
              feature_flags: feature_flags
            }
          ))
          .once
          .returns(ResponseMock.new(
            data: ResponseDataMock.new(
              unresolved_count: expected_unresolved_count
            )
          ))

        service = AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session)

        count = service.generic_results_alert_count
        assert_equal expected_unresolved_count, count
      end

      test "for org" do
        query = Search::Queries::SecurityCenter::SecretScanningQuery::default_query_generic_results
        service = AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session)
        feature_flags = T.let(["stop_using_has_valid_locations"], T::Array[T.any(String, Symbol)])
        if GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GENERIC_SECRETS_BLOCK].enabled?
          feature_flags << :secret_scanning_generic_secrets_block
        end
        SecretScanning::Features::Org::LowerConfidencePatterns.any_instance.stubs(:feature_available?).returns(true)
        GitHub::TokenScanning::Service::Client
          .any_instance
          .stubs(:get_token_counts)
          .with(has_entries(
            {
              low_confidence: true,
              org_selector: GitHub::Proto::SecretScanning::Api::V2::OrgSelector.new(
                owner_id: @org1.id,
                repository_ids: [],
                repository_visibilities: [:REPOSITORY_VISIBILITY_PUBLIC, :REPOSITORY_VISIBILITY_PRIVATE, :REPOSITORY_VISIBILITY_INTERNAL],
              ),
              feature_flags: feature_flags
            }
          ))
          .once
          .returns(ResponseMock.new(
            data: ResponseDataMock.new(
              unresolved_count: 5
            )
          ))
        service = AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session)

        count = service.generic_results_alert_count

        assert_equal 5, count
      end

      test "for org but with user that cannot access any repos" do
        query = Search::Queries::SecurityCenter::SecretScanningQuery::default_query_generic_results
        service = AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session)
        feature_flags = T.let(["stop_using_has_valid_locations"], T::Array[T.any(String, Symbol)])
        if GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GENERIC_SECRETS_BLOCK].enabled?
          feature_flags << :secret_scanning_generic_secrets_block
        end
        SecretScanning::Features::Org::LowerConfidencePatterns.any_instance.stubs(:feature_available?).returns(true)
        GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_token_counts).never

        service = AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session, allowed_repository_ids: [])

        count = service.generic_results_alert_count

        assert_nil count
      end

      test "for repo" do
        query = Search::Queries::SecurityCenter::SecretScanningQuery::default_query_generic_results
        feature_flags = T.let(["stop_using_has_valid_locations"], T::Array[T.any(String, Symbol)])
        if GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GENERIC_SECRETS_BLOCK].enabled?
          feature_flags << :secret_scanning_generic_secrets_block
        end
        SecretScanning::Features::Repo::LowerConfidencePatterns.any_instance.stubs(:feature_available?).returns(true)
        GitHub::TokenScanning::Service::Client
          .any_instance
          .stubs(:get_token_counts)
          .with(has_entries(
            {
              low_confidence: true,
              repo_selector: GitHub::Proto::SecretScanning::Api::V2::RepoSelector.new(repository_id: @repo1a.id),
              feature_flags: feature_flags
            }
          ))
          .once
          .returns(ResponseMock.new(
            data: ResponseDataMock.new(
              unresolved_count: 5
            )
          ))
        service = AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user)

        count = service.generic_results_alert_count

        assert_equal 5, count
      end

      test "handles invalid query" do
        query = "blah"
        service = AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session)
        feature_flags = T.let(["stop_using_has_valid_locations"], T::Array[T.any(String, Symbol)])
        if GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GENERIC_SECRETS_BLOCK].enabled?
          feature_flags << :secret_scanning_generic_secrets_block
        end
        SecretScanning::Features::Org::LowerConfidencePatterns.any_instance.stubs(:feature_available?).returns(true)
        GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_token_counts).never

        service = AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session)

        count = service.generic_results_alert_count

        assert_nil count
      end
    end

    context ".get_alerts" do
      test "handles nil response" do
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once

        sut = AlertQueryService.for_repository(repository: @repo1a, current_user: @user)
        result = sut.get_alerts

        alerts, open_count, closed_count, svc_resp, error = result
        assert_empty alerts
        assert_equal 0, open_count
        assert_equal 0, closed_count
        assert_nil svc_resp
        assert error
      end

      test "returns mapped objects from response" do
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.returns(get_tokens_response)

        result_alerts, _ = AlertQueryService.for_organization(organization: @org1, current_user: @user, user_session: @user_session).get_alerts

        result_alerts.each do |alert|
          assert_instance_of(GitHub::TokenScanning::Service::Token, alert)
          refute_nil(alert.raw_secret)
        end

        tokens_from_api = get_tokens_response.data.try(:tokens)
        assert_equal(result_alerts.length, tokens_from_api.length)
        assert_equal(result_alerts.map(&:id), tokens_from_api.map(&:id))
      end

      context "results category filter" do
        context "generic secrets unavailable" do
          context "low-conf patterns unavailable" do
            context "for business" do
              test "with results:default, get_alerts returns empty response" do
                # Specifying results category in query is invalid. Because query is invalid, get_alerts returns empty
                # response and never calls Client::get_tokens.
                SecretScanning::Features::Business::GenericSecrets.any_instance.stubs(:feature_available?).returns(false)
                SecretScanning::Features::Business::LowerConfidencePatterns.any_instance.stubs(:feature_available?).returns(false)
                query = "#{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::DEFAULT_RESULTS_CATEGORY}"
                GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
                service = AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session)
                result = service.get_alerts
                assert_equal [[], 0, 0, nil, nil], result
              end
            end

            context "for org" do
              test "with results:default, get_alerts returns empty response" do
                # Specifying results in query is invalid. Because query is invalid, get_alerts returns empty
                # response and never calls Client::get_tokens.
                SecretScanning::Features::Org::GenericSecrets.any_instance.stubs(:feature_available?).returns(false)
                SecretScanning::Features::Org::LowerConfidencePatterns.any_instance.stubs(:feature_available?).returns(false)
                query = "#{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::DEFAULT_RESULTS_CATEGORY}"
                GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
                service = AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session)
                result = service.get_alerts
                assert_equal [[], 0, 0, nil, nil], result
              end
            end

            context "for repo" do
              test "with results:default, get_alerts returns empty response" do
                # Specifying results category in query is invalid. Because query is invalid, get_alerts returns empty
                # response and never calls Client::get_tokens.
                SecretScanning::Features::Repo::GenericSecrets.any_instance.stubs(:feature_available?).returns(false)
                SecretScanning::Features::Repo::LowerConfidencePatterns.any_instance.stubs(:feature_available?).returns(false)
                query = "#{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::DEFAULT_RESULTS_CATEGORY}"
                GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
                service = AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user)
                result = service.get_alerts
                assert_equal [[], 0, 0, nil, nil], result
              end
            end
          end
        end

        context "generic secrets available" do
          test "results:default" do
            expected = {
              low_confidence: false,
            }

            SecretScanning::Features::Business::GenericSecrets.any_instance.stubs(:feature_available?).returns(true)
            query = "#{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::DEFAULT_RESULTS_CATEGORY}"
            GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
            AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
          end

          test "results:generic" do
            expected = {
              low_confidence: true,
            }

            SecretScanning::Features::Business::GenericSecrets.any_instance.stubs(:feature_available?).returns(true)
            query = "#{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::GENERIC_RESULTS}"
            GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
            AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
          end

          test "no results category" do
            expected = {
              low_confidence: false,
            }

            query = ""
            SecretScanning::Features::Business::GenericSecrets.any_instance.stubs(:feature_available?).returns(true)
            GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
            AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
          end

          test "invalid results category" do
            query = "#{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:blah"
            SecretScanning::Features::Business::GenericSecrets.any_instance.stubs(:feature_available?).returns(true)
            GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
            AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
          end
        end
      end
    end

    context ".get_alerts - business selector" do
      test "adds selector to request" do
        expected_user_filter = GitHub.enterprise? || TestEnv.test_with_all_emus? ? :ALL : :NONE
        expected = {
          business_selector: {
            organization_ids: @business.organizations.map(&:id),
            repository_ids: [],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ],
            id: @business.id,
            user_ids: [],
            user_filter: expected_user_filter,
            owner_types: [],
            excluded_owner_types: [],
          }
        }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, current_user: @user, user_session: @user_session).get_alerts
      end

      test "adds selector to request for ESM, behavior should be the same as business owner" do
        expected_user_filter = GitHub.enterprise? || TestEnv.test_with_all_emus? ? :ALL : :NONE
        expected = {
          business_selector: {
            organization_ids: @business.organizations.map(&:id),
            repository_ids: [],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ],
            id: @business.id,
            user_ids: [],
            user_filter: expected_user_filter,
            owner_types: [],
            excluded_owner_types: [],
          }
        }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, current_user: @enterprise_security_manager, user_session: @esm_session).get_alerts
      end


      # Simple owner filter tests
      test "owner filter - single include" do
        expected = {
          business_selector: {
            organization_ids: [@org1.id],
            repository_ids: [],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ],
            id: @business.id,
            user_ids: [],
            user_filter: :NONE,
            owner_types: [],
            excluded_owner_types: [],
          }
        }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))

        query = "owner:#{@org1.name}"
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
      end

      test "owner filter - single exclude" do
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once
          .with { |params| params[:business_selector][:organization_ids].include?(@org1.id) }
          .with { |params| params[:business_selector][:organization_ids].include?(@org3.id) }
          .with { |params| params[:business_selector][:organization_ids].exclude?(@org2.id) }

        query = "-owner:#{@org2.name}"
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
      end

      test "owner filter - single conflict" do
        query = "owner:#{@org3.name} -owner:#{@org3.name}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
      end

      test "owner filter - conflict with include" do
        expected = {
          business_selector: {
            organization_ids: [@org2.id],
            repository_ids: [],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ],
            id: @business.id,
            user_ids: [],
            user_filter: :NONE,
            owner_types: [],
            excluded_owner_types: [],
          }
        }

        query = "owner:#{@org1.name},#{@org2.name} -owner:#{@org1.name}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
      end

      test "owner filter - conflict with exclude" do
        query = "owner:#{@org1.name} -owner:#{@org1.name},#{@org2.name}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
      end

      test "owner filter - invalid value" do
        query = "owner:#{SecureRandom.uuid}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
      end

      test "owner filter with EMUs - single include", skip_enterprise: true do
        expected = {
          business_selector: {
            organization_ids: [@emu_org1.id],
            repository_ids: [],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ],
            id: @emu_biz.id,
            user_ids: [],
            user_filter: :NONE,
            owner_types: [],
            excluded_owner_types: [],
          }
        }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))

        query = "owner:#{@emu_org1.name}"
        AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
      end

      test "owner filter - exclude", skip_enterprise: true do
        expected = {
          business_selector: {
            organization_ids: [@emu_org3.id],
            repository_ids: [],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ],
            id: @emu_biz.id,
            user_ids: [],
            user_filter: :ALL,
            owner_types: [],
            excluded_owner_types: [],
          }
        }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))

        query = "-owner:#{@emu_org1.name},#{@emu_org2.name}"
        AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
      end

      context "user_filter", skip_enterprise: true do
        test "includes users" do
          expected = {
            business_selector: {
              organization_ids: @emu_biz.organizations.map(&:id),
              repository_ids: [],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @emu_biz.id,
              user_ids: [],
              user_filter: :ALL,
              owner_types: [],
              excluded_owner_types: [],
            }
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, current_user: @emu_owner, user_session: @user_session).get_alerts
        end

        test "owner filter - single include" do
          expected = {
            business_selector: {
              organization_ids: [],
              repository_ids: [],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @emu_biz.id,
              user_ids: [@emu_user1.id],
              user_filter: :ONLY,
              owner_types: [],
            excluded_owner_types: [],
            }
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))

          query = "owner:#{@emu_user1.name}"
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end

        test "single exclude" do
          expected = {
            business_selector: {
              organization_ids: @emu_biz.organizations.map(&:id),
              repository_ids: [],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @emu_biz.id,
              user_ids: [@emu_user1.id],
              user_filter: :EXCEPT,
              owner_types: [],
            excluded_owner_types: [],
            }
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))

          query = "-owner:#{@emu_user1.name}"
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end

        test "single conflict" do
          query = "owner:#{@emu_user1.name} -owner:#{@emu_user1.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end

        test "conflict with include" do
          expected = {
            business_selector: {
              organization_ids: [],
              repository_ids: [],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @emu_biz.id,
              user_ids: [@emu_user1.id],
              user_filter: :ONLY,
              owner_types: [],
            excluded_owner_types: [],
            }
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))

          query = "owner:#{@emu_user1.name},#{@emu_user2.name} -owner:#{@emu_user2.name}"
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end

        test "conflict with exclude" do
          query = "owner:#{@emu_user1.name} -owner:#{@emu_user1.name},#{@emu_user2.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end

        context "if the current user is not a business owner" do
          test "filters alerts to only be from the current user's repositories" do
            rando = create(:emu, business: @emu_biz)
            expected = {
              business_selector: {
                organization_ids: @emu_biz.organizations.map(&:id),
                repository_ids: [],
                repos_are_excluded: false,
                repository_visibilities: [
                  :REPOSITORY_VISIBILITY_PUBLIC,
                  :REPOSITORY_VISIBILITY_PRIVATE,
                  :REPOSITORY_VISIBILITY_INTERNAL
                ],
                id: @emu_biz.id,
                user_ids: [rando.id],
                user_filter: :ONLY,
                owner_types: [],
                excluded_owner_types: [],
              }
            }
            GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
            AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, current_user: rando, user_session: @user_session).get_alerts
          end

          test "returns nothing if they exclude themself" do
            rando = create(:emu, business: @emu_biz)
            expected = {
              business_selector: {
                organization_ids: @emu_biz.organizations.map(&:id),
                repository_ids: [],
                repos_are_excluded: false,
                repository_visibilities: [
                  :REPOSITORY_VISIBILITY_PUBLIC,
                  :REPOSITORY_VISIBILITY_PRIVATE,
                  :REPOSITORY_VISIBILITY_INTERNAL
                ],
                id: @emu_biz.id,
                user_ids: [],
                user_filter: :NONE,
                owner_types: [],
                excluded_owner_types: [],
              }
            }
            query = "-owner:#{rando.name}"
            GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
            AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, current_user: rando, user_session: @user_session, query: query).get_alerts
          end

          test "swaps user_filter to only include themselves if they try to exclude a different user" do
            rando = create(:emu, business: @emu_biz)
            expected = {
              business_selector: {
                organization_ids: @emu_biz.organizations.map(&:id),
                repository_ids: [],
                repos_are_excluded: false,
                repository_visibilities: [
                  :REPOSITORY_VISIBILITY_PUBLIC,
                  :REPOSITORY_VISIBILITY_PRIVATE,
                  :REPOSITORY_VISIBILITY_INTERNAL
                ],
                id: @emu_biz.id,
                user_ids: [rando.id],
                user_filter: :ONLY,
                owner_types: [],
                excluded_owner_types: [],
              }
            }
            query = "-owner:#{@emu_user1.name}"
            GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
            AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, current_user: rando, user_session: @user_session, query: query).get_alerts
          end
        end


        test "invalid value" do
          query = "owner:foobar"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end
      end

      context "owner filter", skip_enterprise: true do
        test "includes only users when a user is queried" do
          expected = {
            business_selector: {
              organization_ids: [],
              repository_ids: [],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @emu_biz.id,
              user_ids: [@emu_user1.id],
              user_filter: :ONLY,
              owner_types: [],
              excluded_owner_types: [],
            }
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))

          query = "owner:#{@emu_user1.name}"
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end

        test "excludes users when a user is negated and includes orgs" do
          expected = {
            business_selector: {
              organization_ids: @emu_biz.organizations.map(&:id),
              repository_ids: [],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @emu_biz.id,
              user_ids: [@emu_user1.id],
              user_filter: :EXCEPT,
              owner_types: [],
              excluded_owner_types: [],
            }
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))

          query = "-owner:#{@emu_user1.name}"
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end

        test "excludes all users when all users are negated and includes orgs" do
          expected = {
            business_selector: {
              organization_ids: @emu_biz.organizations.map(&:id),
              repository_ids: [],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @emu_biz.id,
              user_ids: [@emu_user1.id, @emu_user2.id, @emu_user3.id],
              user_filter: :EXCEPT,
              owner_types: [],
              excluded_owner_types: [],
            }
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))

          query = "-owner:#{@emu_user1.name},#{@emu_user2.name},#{@emu_user3.name}"
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end

        test "includes only orgs when an org is queried" do
          expected = {
            business_selector: {
              organization_ids: [@emu_org1.id],
              repository_ids: [],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @emu_biz.id,
              user_ids: [],
              user_filter: :NONE,
              owner_types: [],
              excluded_owner_types: [],
            }
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))

          query = "owner:#{@emu_org1.name}"
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end

        test "excludes orgs when an org is negated and sets users filter to ALL" do
          expected = {
            business_selector: {
              organization_ids: @emu_biz.organizations.map(&:id).filter { |id| id != @emu_org1.id },
              repository_ids: [],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @emu_biz.id,
              user_ids: [],
              user_filter: :ALL,
              owner_types: [],
              excluded_owner_types: [],
            }
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))

          query = "-owner:#{@emu_org1.name}"
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end

        test "excludes all orgs when an all orgs are negated and sets users filter to ALL" do
          expected = {
            business_selector: {
              organization_ids: [],
              repository_ids: [],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @emu_biz.id,
              user_ids: [],
              user_filter: :ALL,
              owner_types: [],
              excluded_owner_types: [],
            }
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))

          query = "-owner:#{@emu_biz.organizations.map(&:name).join(',')}"
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end

        test "includes both users and orgs when they're queried in combination" do
          expected = {
            business_selector: {
              organization_ids: [@emu_org1.id],
              repository_ids: [],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @emu_biz.id,
              user_ids: [@emu_user1.id],
              user_filter: :ONLY,
              owner_types: [],
              excluded_owner_types: [],
            }
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))

          query = "owner:#{@emu_org1.name},#{@emu_user1.name}"
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end

        test "excludes users and orgs when negated in query" do
          expected = {
            business_selector: {
              organization_ids: [@emu_org3.id],
              repository_ids: [],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @emu_biz.id,
              user_ids: [@emu_user1.id],
              user_filter: :EXCEPT,
              owner_types: [],
              excluded_owner_types: [],
            }
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))

          query = "-owner:#{@emu_org1.name},#{@emu_org2},#{@emu_user1}"
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end

        test "invalid value does not call tss api" do
          query = "owner:invalid-owner"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end
      end

      context "owner type filter", skip_enterprise: true do
        test "includes only users when the owner type user is queried" do
          expected = {
            business_selector: {
              organization_ids: @emu_biz.organizations.map(&:id),
              repository_ids: [],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @emu_biz.id,
              user_ids: [],
              user_filter: :ALL,
              owner_types: [:OWNER_TYPE_USER],
              excluded_owner_types: [],
            }
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))

          query = "owner-type:user"
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end

        test "excludes users when owner type user is negated and includes orgs" do
          expected = {
            business_selector: {
              organization_ids: @emu_biz.organizations.map(&:id),
              repository_ids: [],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @emu_biz.id,
              user_ids: [],
              user_filter: :ALL,
              owner_types: [],
              excluded_owner_types: [:OWNER_TYPE_USER],
            }
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))

          query = "-owner-type:user"
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end

        test "includes only orgs when owner type org is queried" do
          expected = {
            business_selector: {
              organization_ids: @emu_biz.organizations.map(&:id),
              repository_ids: [],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @emu_biz.id,
              user_ids: [],
              user_filter: :ALL,
              owner_types: [:OWNER_TYPE_ORGANIZATION],
              excluded_owner_types: [],
            }
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))

          query = "owner-type:organization"
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end

        test "exludes orgs when owner type org is negated" do
          expected = {
            business_selector: {
              organization_ids: @emu_biz.organizations.map(&:id),
              repository_ids: [],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @emu_biz.id,
              user_ids: [],
              user_filter: :ALL,
              owner_types: [],
              excluded_owner_types: [:OWNER_TYPE_ORGANIZATION],
            }
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))

          query = "-owner-type:organization"
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end

        test "includes both users and orgs when they're queried in combination" do
          expected = {
            business_selector: {
              organization_ids: @emu_biz.organizations.map(&:id),
              repository_ids: [],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @emu_biz.id,
              user_ids: [],
              user_filter: :ALL,
              owner_types: [:OWNER_TYPE_USER, :OWNER_TYPE_ORGANIZATION],
              excluded_owner_types: [],
            }
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))

          query = "owner-type:user,organization"
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end

        test "excludes both users and orgs when they're negated in combination" do
          expected = {
            business_selector: {
              organization_ids: @emu_biz.organizations.map(&:id),
              repository_ids: [],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @emu_biz.id,
              user_ids: [],
              user_filter: :ALL,
              owner_types: [],
              excluded_owner_types: [:OWNER_TYPE_USER, :OWNER_TYPE_ORGANIZATION],
            }
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))

          query = "-owner-type:user,organization"
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end

        test "exclude orgs but query org owner should not fail" do
          expected = {
            business_selector: {
              organization_ids: [@emu_org1.id],
              repository_ids: [],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @emu_biz.id,
              user_ids: [],
              user_filter: :NONE,
              owner_types: [],
              excluded_owner_types: [:OWNER_TYPE_ORGANIZATION],
            }
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))

          query = "-owner-type:organization owner:#{@emu_org1.name}"
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end

        test "invalid value does not call tss api" do
          query = "owner-type:invalid"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end

        test "invalid user value does not call tss api" do
          query = "owner-type:user -owner-type:user"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end

        test "invalid org value does not call tss api" do
          query = "owner-type:organization -owner-type:organization"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_alerts
        end
      end

      test "repo filter - single include" do
        expected_user_filter = GitHub.enterprise? || TestEnv.test_with_all_emus? ? :ALL : :NONE
        expected = {
          business_selector: {
            organization_ids: @business.organizations.map(&:id),
            repository_ids: [@repo1a.id],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ],
            id: @business.id,
            user_ids: [],
            user_filter: expected_user_filter,
            owner_types: [],
            excluded_owner_types: [],
          }
        }

        query = "repo:#{@repo1a.nwo}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
      end

      test "repo filter - single exclude" do
        expected_user_filter = GitHub.enterprise? || TestEnv.test_with_all_emus? ? :ALL : :NONE
        expected = {
          business_selector: {
            organization_ids: @business.organizations.map(&:id),
            repository_ids: [@repo1a.id],
            repos_are_excluded: true,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ],
            id: @business.id,
            user_ids: [],
            user_filter: expected_user_filter,
            owner_types: [],
            excluded_owner_types: [],
          }
        }

        query = "-repo:#{@repo1a.nwo}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
      end

      test "repo filter - single conflict" do
        query = "repo:#{@repo1a.nwo} -repo:#{@repo1a.nwo}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
      end

      test "repo filter - conflict with include" do
        expected_user_filter = GitHub.enterprise? || TestEnv.test_with_all_emus? ? :ALL : :NONE
        expected = {
          business_selector: {
            organization_ids: @business.organizations.map(&:id),
            repository_ids: [@repo1b.id],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ],
            id: @business.id,
            user_ids: [],
            user_filter: expected_user_filter,
            owner_types: [],
            excluded_owner_types: [],
          }
        }

        query = "repo:#{@repo1a.nwo},#{@repo1b.nwo} -repo:#{@repo1a.nwo}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
      end

      test "repo filter - conflict with exclude" do
        query = "repo:#{@repo1a.nwo} -repo:#{@repo1a.nwo},#{@repo1c.nwo}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
      end

      test "repo filter - invalid value" do
        query = "repo:#{SecureRandom.uuid}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
      end

      test "repo filter - caps number of repo IDs sent" do
        expected = {
          business_selector: has_entries(
            repository_ids: any_of([@repo1a.id], [@repo1b.id]),
            repos_are_excluded: false,
          ),
        }

        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
        AlertQueryService::BusinessScopeStrategy.stub_const(:REPO_IDS_SIZE_LIMIT, 1) do
          query = "repo:#{@repo1a.nwo},#{@repo1b.nwo}"
          AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
        end
      end

      context "team filter" do
        test "single include" do
          expected_user_filter = GitHub.enterprise? || TestEnv.test_with_all_emus? ? :ALL : :NONE
          expected = {
            business_selector: {
              organization_ids: @business.organizations.map(&:id),
              repository_ids: [@repo1a.id],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @business.id,
              user_ids: [],
              user_filter: expected_user_filter,
              owner_types: [],
            excluded_owner_types: [],
            }
          }

          query = "team:#{@org1.name}/#{@team1a.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
          AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
        end

        test "single exclude" do
          expected_user_filter = GitHub.enterprise? || TestEnv.test_with_all_emus? ? :ALL : :NONE
          expected = {
            business_selector: {
              organization_ids: @business.organizations.map(&:id),
              repository_ids: [@repo1a.id],
              repos_are_excluded: true,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @business.id,
              user_ids: [],
              user_filter: expected_user_filter,
              owner_types: [],
            excluded_owner_types: [],
            }
          }

          query = "-team:#{@org1.name}/#{@team1a.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
          AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
        end

        test "single conflict" do
          query = "team:#{@org1.name}/#{@team1a.name} -team:#{@org1.name}/#{@team1a.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
          AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
        end

        test "conflict with include" do
          expected_user_filter = GitHub.enterprise? || TestEnv.test_with_all_emus? ? :ALL : :NONE
          expected = {
            business_selector: {
              organization_ids: @business.organizations.map(&:id),
              repository_ids: [@repo1b.id],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @business.id,
              user_ids: [],
              user_filter: expected_user_filter,
              owner_types: [],
            excluded_owner_types: [],
            }
          }

          query = "team:#{@org1.name}/#{@team1a.name},#{@org1.name}/#{@team1b.name} -team:#{@org1.name}/#{@team1a.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
          AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
        end

        test "conflict with exclude" do
          query = "team:#{@org1.name}/#{@team1a.name} -team:#{@org1.name}/#{@team1a.name},#{@org1.name}/#{@team1c.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
          AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
        end

        test "invalid value" do
          query = "team:#{SecureRandom.uuid}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
          AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
        end

        test "user permissions to see team" do
          member = create(:user)
          @business.add_owner(member, actor: nil)
          @org1.add_member(member)
          query = "team:#{@org1.name}/#{@team1a.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
          AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: member, user_session: @user_session).get_alerts

          expected_user_filter = GitHub.enterprise? || TestEnv.test_with_all_emus? ? :ALL : :NONE
          expected = {
            business_selector: {
              organization_ids: @business.organizations.map(&:id),
              repository_ids: [@repo1b.id],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @business.id,
              user_ids: [],
              user_filter: expected_user_filter,
              owner_types: [],
            excluded_owner_types: [],
            }
          }

          query = "team:#{@org1.name}/#{@team1b.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
          AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: member, user_session: @user_session).get_alerts
        end

        test "caps number of repo IDs sent" do
          ::SecurityCenter::FeatureFlagHelper.stubs(:business_secret_scanning_teams_filter_enabled?).returns(true)
          expected = {
            business_selector: has_entries(
              repository_ids: any_of([@repo1a.id], [@repo1b.id]),
              repos_are_excluded: false,
            ),
          }

          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
          AlertQueryService::BusinessScopeStrategy.stub_const(:REPO_IDS_SIZE_LIMIT, 1) do
            query = "team:#{@team1a.combined_slug},#{@team1b.combined_slug}"
            AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
          end
        end
      end

      context "topic filter" do
        test "single include" do
          expected_user_filter = GitHub.enterprise? || TestEnv.test_with_all_emus? ? :ALL : :NONE
          expected = {
            business_selector: {
              organization_ids: @business.organizations.map(&:id),
              repository_ids: [@repo1a.id],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @business.id,
              user_ids: [],
              user_filter: expected_user_filter,
              owner_types: [],
            excluded_owner_types: [],
            }
          }

          query = "topic:#{@topica.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
          AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
        end

        test "single exclude" do
          expected_user_filter = GitHub.enterprise? || TestEnv.test_with_all_emus? ? :ALL : :NONE
          expected = {
            business_selector: {
              organization_ids: @business.organizations.map(&:id),
              repository_ids: [@repo1a.id],
              repos_are_excluded: true,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @business.id,
              user_ids: [],
              user_filter: expected_user_filter,
              owner_types: [],
            excluded_owner_types: [],
            }
          }

          query = "-topic:#{@topica.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
          AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
        end

        test "single conflict" do
          query = "topic:#{@topica.name} -topic:#{@topica.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
          AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
        end

        test "conflict with include" do
          expected_user_filter = GitHub.enterprise? || TestEnv.test_with_all_emus? ? :ALL : :NONE
          expected = {
            business_selector: {
              organization_ids: @business.organizations.map(&:id),
              repository_ids: [@repo1b.id],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @business.id,
              user_ids: [],
              user_filter: expected_user_filter,
              owner_types: [],
            excluded_owner_types: [],
            }
          }

          query = "topic:#{@topica.name},#{@topicb.name} -topic:#{@topica.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
          AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
        end

        test "conflict with exclude" do
          query = "topic:#{@topica.name} -topic:#{@topica.name},#{@topicc.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
          AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
        end

        test "invalid value" do
          query = "topic:#{SecureRandom.uuid}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
          AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
        end

        test "caps number of repo IDs sent" do
          ::SecurityCenter::FeatureFlagHelper.stubs(:business_secret_scanning_topic_filter_enabled?).returns(true)
          expected = {
            business_selector: has_entries(
              repository_ids: any_of([@repo1a.id], [@repo1b.id]),
              repos_are_excluded: false,
            ),
          }

          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
          AlertQueryService::BusinessScopeStrategy.stub_const(:REPO_IDS_SIZE_LIMIT, 1) do
            query = "topic:#{@topica.name},#{@topicb.name}"
            AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_alerts
          end
        end
      end
    end

    context ".get_alerts - org selector" do
      test "adds selector to request" do
        expected = {
          org_selector: {
            owner_id: @org1.id,
            repository_ids: [],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ]
          }
        }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
        AlertQueryService.for_organization(organization: @org1, current_user: @user, user_session: @user_session).get_alerts
      end

      test "repo filter - single include" do
        expected = {
          org_selector: {
            owner_id: @org1.id,
            repository_ids: [@repo1a.id],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ]
          }
        }

        query = "repo:#{@repo1a.name}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
        AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_alerts
      end

      test "repo filter - single exclude" do
        expected = {
          org_selector: {
            owner_id: @org1.id,
            repository_ids: [@repo1a.id],
            repos_are_excluded: true,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ]
          }
        }

        query = "-repo:#{@repo1a.name}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
        AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_alerts
      end

      test "repo filter - single conflict" do
        query = "repo:#{@repo1a.name} -repo:#{@repo1a.name}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_alerts
      end

      test "repo filter - conflict with include" do
        expected = {
          org_selector: {
            owner_id: @org1.id,
            repository_ids: [@repo1b.id],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ]
          }
        }

        query = "repo:#{@repo1a.name},#{@repo1b.name} -repo:#{@repo1a.name}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
        AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_alerts
      end

      test "repo filter - conflict with exclude" do
        query = "repo:#{@repo1a.name} -repo:#{@repo1a.name},#{@repo1c.name}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_alerts
      end

      test "repo filter - invalid value" do
        query = "repo:#{SecureRandom.uuid}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_alerts
      end

      test "repo filter - caps number of repo IDs sent" do
        expected = {
          org_selector: has_entries(
            repository_ids: any_of([@repo1a.id], [@repo1b.id]),
            repos_are_excluded: false,
          ),
        }

        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
        AlertQueryService::OrganizationScopeStrategy.stub_const(:REPO_IDS_SIZE_LIMIT, 1) do
          query = "repo:#{@repo1a.name},#{@repo1b.name}"
          AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_alerts
        end
      end

      context "team filter" do
        test "single include" do
          expected = {
            org_selector: {
              owner_id: @org1.id,
              repository_ids: [@repo1a.id],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ]
            }
          }

          query = "team:#{@team1a.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
          AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_alerts
        end

        test "single exclude" do
          expected = {
            org_selector: {
              owner_id: @org1.id,
              repository_ids: [@repo1a.id],
              repos_are_excluded: true,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ]
            }
          }

          query = "-team:#{@team1a.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
          AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_alerts
        end

        test "single conflict" do
          query = "team:#{@team1a.name} -team:#{@team1a.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
          AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_alerts
        end

        test "conflict with include" do
          expected = {
            org_selector: {
              owner_id: @org1.id,
              repository_ids: [@repo1b.id],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ]
            }
          }

          query = "team:#{@team1a.name},#{@team1b.name} -team:#{@team1a.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
          AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_alerts
        end

        test "conflict with exclude" do
          query = "team:#{@team1a.name} -team:#{@team1a.name},#{@team1c.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
          AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_alerts
        end

        test "invalid value" do
          query = "team:#{SecureRandom.uuid}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
          AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_alerts
        end

        test "user permissions to see team" do
          member = create(:user)
          @org1.add_member(member)
          query = "team:#{@team1a.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
          AlertQueryService.for_organization(organization: @org1, query: query, current_user: member, user_session: @user_session).get_alerts

          expected = {
            org_selector: {
              owner_id: @org1.id,
              repository_ids: [@repo1b.id],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ]
            }
          }

          query = "team:#{@team1b.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
          AlertQueryService.for_organization(organization: @org1, query: query, current_user: member, user_session: @user_session).get_alerts
        end

        test "caps number of repo IDs sent" do
          expected = {
            org_selector: has_entries(
              repository_ids: any_of([@repo1a.id], [@repo1b.id]),
              repos_are_excluded: false,
            ),
          }

          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
          AlertQueryService::OrganizationScopeStrategy.stub_const(:REPO_IDS_SIZE_LIMIT, 1) do
            query = "team:#{@team1a.combined_slug},#{@team1b.combined_slug}"
            AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_alerts
          end
        end
      end

      context "topic filter" do
        test "single include" do
          expected = {
            org_selector: {
              owner_id: @org1.id,
              repository_ids: [@repo1a.id],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ]
            }
          }

          query = "topic:#{@topica.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
          AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_alerts
        end

        test "single exclude" do
          expected = {
            org_selector: {
              owner_id: @org1.id,
              repository_ids: [@repo1a.id],
              repos_are_excluded: true,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ]
            }
          }

          query = "-topic:#{@topica.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
          AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_alerts
        end

        test "single conflict" do
          query = "topic:#{@topica.name} -topic:#{@topica.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
          AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_alerts
        end

        test "conflict with include" do
          expected = {
            org_selector: {
              owner_id: @org1.id,
              repository_ids: [@repo1b.id],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ]
            }
          }

          query = "topic:#{@topica.name},#{@topicb.name} -topic:#{@topica.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
          AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_alerts
        end

        test "conflict with exclude" do
          query = "topic:#{@topica.name} -topic:#{@topica.name},#{@topicc.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
          AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_alerts
        end

        test "invalid value" do
          query = "topic:#{SecureRandom.uuid}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
          AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_alerts
        end

        test "caps number of repo IDs sent" do
          expected = {
            org_selector: has_entries(
              repository_ids: any_of([@repo1a.id], [@repo1b.id]),
              repos_are_excluded: false,
            ),
          }

          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
          AlertQueryService::OrganizationScopeStrategy.stub_const(:REPO_IDS_SIZE_LIMIT, 1) do
            query = "topic:#{@topica.name},#{@topicb.name}"
            AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_alerts
          end
        end
      end
    end

    context ".get_alerts - org selector with allowed repositories" do
      test "default" do
        expected = {
          org_selector: {
            owner_id: @org1.id,
            repository_ids: [@repo1a.id, @repo1b.id],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ]
          }
        }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
        AlertQueryService.for_organization(organization: @org1, allowed_repository_ids: [@repo1a.id, @repo1b.id], current_user: @user, user_session: @user_session).get_alerts
      end

      test "none allowed" do
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_organization(organization: @org1, allowed_repository_ids: [], current_user: @user, user_session: @user_session).get_alerts

        # Make sure adding a filter doesn't get around the lack of allowed repo IDs
        query = "repo:#{@repo1a.name}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_organization(organization: @org1, allowed_repository_ids: [], query: query, current_user: @user, user_session: @user_session).get_alerts

        # Make sure adding a negated filter doesn't get around the lack of allowed repo IDs
        query = "-repo:#{@repo1a.name}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_organization(organization: @org1, allowed_repository_ids: [], query: query, current_user: @user, user_session: @user_session).get_alerts
      end

      test "single include" do
        expected = {
          org_selector: {
            owner_id: @org1.id,
            repository_ids: [@repo1a.id],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ]
          }
        }

        query = "repo:#{@repo1a.name}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
        AlertQueryService.for_organization(organization: @org1, allowed_repository_ids: [@repo1a.id, @repo1b.id], query: query, current_user: @user, user_session: @user_session).get_alerts
      end

      test "single include not allowed" do
        query = "repo:#{@repo1c.name}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_organization(organization: @org1, allowed_repository_ids: [@repo1a.id, @repo1b.id], query: query, current_user: @user, user_session: @user_session).get_alerts
      end

      test "single exclude" do
        expected = {
          org_selector: {
            owner_id: @org1.id,
            repository_ids: [@repo1b.id],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ]
          }
        }

        query = "-repo:#{@repo1a.name}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
        AlertQueryService.for_organization(organization: @org1, allowed_repository_ids: [@repo1a.id, @repo1b.id], query: query, current_user: @user, user_session: @user_session).get_alerts
      end

      test "single exclude not allowed" do
        expected = {
          org_selector: {
            owner_id: @org1.id,
            repository_ids: [@repo1a.id, @repo1b.id],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ]
          }
        }

        query = "-repo:#{@repo1c.name}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
        AlertQueryService.for_organization(organization: @org1, allowed_repository_ids: [@repo1a.id, @repo1b.id], query: query, current_user: @user, user_session: @user_session).get_alerts
      end
    end

    context ".get_alerts - repo selector" do
      test "adds selector to request" do
        expected = {
          repo_selector: {
            repository_id: @repo1a.id
          }
        }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
        AlertQueryService.for_repository(repository: @repo1a, current_user: @user).get_alerts
      end
    end

    context ".get_alerts - state" do
      test "no filter" do
        query = ""
        expected = { token_state: :NO_STATE }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "open and closed" do
        query = "is:open,closed"
        expected = { token_state: :NO_STATE }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "explicit open" do
        query = "is:open"
        expected = { token_state: :OPEN }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "explicit closed" do
        query = "is:closed"
        expected = { token_state: :RESOLVED }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "invalid value" do
        query = "is:foobar"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end
    end

    context ".get_alerts - secret type filter" do
      test "no filter" do
        query = ""
        expected = { token_slugs: [], exclude_token_slugs: [] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "single include" do
        query = "secret-type:abc"
        expected = { token_slugs: ["abc"], exclude_token_slugs: [] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "single exclude" do
        query = "-secret-type:def"
        expected = { token_slugs: [], exclude_token_slugs: ["def"] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "conflict" do
        query = "secret-type:abc -secret-type:abc"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "conflict with include" do
        query = "secret-type:abc,def -secret-type:abc"
        expected = { token_slugs: ["def"], exclude_token_slugs: [] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "conflict with exclude" do
        query = "secret-type:abc -secret-type:abc,def"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end
    end

    context ".get_alerts - provider filter" do
      test "no filter" do
        query = ""
        expected = { token_providers: [], exclude_token_providers: [] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "single include" do
        query = "provider:abc"
        expected = { token_providers: ["abc"], exclude_token_providers: [] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "single exclude" do
        query = "-provider:def"
        expected = { token_providers: [], exclude_token_providers: ["def"] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "conflict" do
        query = "provider:abc -provider:abc"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "conflict with include" do
        query = "provider:abc,def -provider:abc"
        expected = { token_providers: ["def"], exclude_token_providers: [] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "conflict with exclude" do
        query = "provider:abc -provider:abc,def"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end
    end

    context ".get_alerts - resolution filter" do
      test "no filter" do
        query = ""
        expected = { resolution: [], exclude_resolutions: [] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "single include" do
        query = "resolution:revoked"
        expected = { resolution: [:REVOKED], exclude_resolutions: [] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "single exclude" do
        query = "-resolution:used-in-tests"
        expected = { resolution: [], exclude_resolutions: [:USED_IN_TESTS] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "conflict" do
        query = "resolution:revoked -resolution:revoked"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "conflict with include" do
        query = "resolution:revoked,wont-fix -resolution:wont-fix"
        expected = { resolution: [:REVOKED], exclude_resolutions: [] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "conflict with exclude" do
        query = "resolution:revoked -resolution:revoked,false-positive"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end
    end

    context ".get_alerts - validity filter" do
      test "no filter" do
        query = ""
        expected = { validity: [] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "single include" do
        query = "validity:active"
        expected = { validity: [:TOKEN_VALIDITY_ACTIVE] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "inactive includes revoked" do
        query = "validity:inactive"
        expected = { validity: [:TOKEN_VALIDITY_INACTIVE, :TOKEN_VALIDITY_REVOKED] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "unknown includes unverifiable" do
        query = "validity:unknown"
        expected = { validity: [:TOKEN_VALIDITY_UNKNOWN, :TOKEN_VALIDITY_UNVERIFIABLE] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "single exclude" do
        query = "-validity:unknown"
        expected = { validity: [] } # exclude not yet supported
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "conflict" do
        query = "validity:inactive -validity:inactive"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "conflict with include" do
        query = "validity:active,inactive -validity:inactive"
        expected = { validity: [:TOKEN_VALIDITY_ACTIVE] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "conflict with exclude" do
        query = "validity:active -validity:active,inactive"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end
    end

    context ".get_alerts - bypassed filter" do
      test "no filter" do
        query = ""
        expected = { bypassed: false }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "single include" do
        query = "bypassed:true"
        expected = { bypassed: true }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "single exclude" do
        query = "-bypassed:true"
        expected = { bypassed: false } # exclude not yet supported
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "conflict" do
        query = "bypassed:true -bypassed:true"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "conflict with include" do
        query = "bypassed:true,false -bypassed:false"
        expected = { bypassed: true }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "conflict with exclude" do
        query = "bypassed:true -bypassed:true,false"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end
    end

    context ".get_alerts - public leaks filter" do
      test "no filter" do
        query = ""
        expected = { publicly_leaked: false }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      context "valid queries" do
        test_cases = [
          "is:open,publicly-leaked",
          "is:publicly-leaked,open",
          "is:open is:publicly-leaked",
          "is:publicly-leaked is:open",
          "is:open is_publicly_leaked:true",
          "is_publicly_leaked:true is:open",
        ]
        test_cases.each do |query|
          test query do
            expected = { publicly_leaked: true }
            GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
            AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
          end
        end
      end

      test "invalid query" do
        query = "is_publicly_leaked:false"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end
    end

    context ".get_alerts - multi-repository filter" do
      test "no filter" do
        query = ""
        expected = { multi_repo: false }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      context "valid queries" do
        test_cases = [
          "is:open,multi-repository",
          "is:multi-repository,open",
          "is:open is:multi-repository",
          "is:multi-repository is:open",
          "is:open is_multi_repository:true",
          "is_multi_repository:true is:open",
        ]
        test_cases.each do |query|
          test query do
            expected = { multi_repo: true }
            GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
            AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
          end
        end
      end

      test "invalid query" do
        query = "is_multi_repository:false"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).never
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end
    end

    context ".get_alerts - sort" do
      test "no filter" do
        query = ""
        expected = { sort_order: :CREATED_DESCENDING }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "explicit created desc" do
        query = "sort:created-desc"
        expected = { sort_order: :CREATED_DESCENDING }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end

      test "invalid value" do
        query = "sort:foobar"
        expected = { sort_order: :CREATED_DESCENDING }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entry(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_alerts
      end
    end

    context ".get_alerts - paging" do
      test "default values" do
        expected = { page: 1, limit: 25 }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, current_user: @user).get_alerts
      end

      test "explicit values" do
        expected = { page: 7, limit: 42 }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, current_user: @user).get_alerts(page: 7, per_page: 42)
      end
    end

    context ".get_alerts - tenant filtering", skip_enterprise: true do
      test "only rows belonging to the business are returned" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        get_tokens_response = ResponseMock.new(
          data: GitHub::Proto::SecretScanning::Api::V2::GetTokensResponse.new(
            tokens: [
              GitHub::Proto::SecretScanning::Api::V2::Token.new(
                created_at: Time.parse("2021-05-05"),
                first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(path: "path/to/file.rb"),
                id: 1,
                label: "Amazon AWS Secret Access Key",
                repository_id: @repo1a.id,
                number: 1
              ),
              GitHub::Proto::SecretScanning::Api::V2::Token.new(
                created_at: Time.parse("2021-05-05"),
                first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(path: "path/to/file.rb"),
                id: 2,
                label: "Amazon AWS Secret Access Key",
                repository_id: @other_business_org_repo.id,
                number: 1
              ),
            ]
          )
        )

        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).returns(get_tokens_response)

        results, _ = AlertQueryService.for_business(business: @business, organizations: @business.organizations, current_user: @user, user_session: @user_session).get_alerts

        assert_equal(1, results.count)
        assert_equal(@repo1a.id, results[0]&.repository.id)
        assert_dogstats_increment(1, "security_center.access_violation", tags: ["feature:secret_scanning", "scope:business"])
      end

      test "only rows belonging to the organization are returned" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        get_tokens_response = ResponseMock.new(
          data: GitHub::Proto::SecretScanning::Api::V2::GetTokensResponse.new(
            tokens: [
              GitHub::Proto::SecretScanning::Api::V2::Token.new(
                created_at: Time.parse("2021-05-05"),
                first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(path: "path/to/file.rb"),
                id: 1,
                label: "Amazon AWS Secret Access Key",
                repository_id: @repo1a.id,
                number: 1
              ),
              GitHub::Proto::SecretScanning::Api::V2::Token.new(
                created_at: Time.parse("2021-05-05"),
                first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(path: "path/to/file.rb"),
                id: 2,
                label: "Amazon AWS Secret Access Key",
                repository_id: @other_business_org_repo.id,
                number: 1
              ),
            ]
          )
        )

        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).returns(get_tokens_response)

        results, _ = AlertQueryService.for_organization(organization: @org1, current_user: @user, user_session: @user_session).get_alerts

        assert_equal(1, results.count)
        assert_equal(@repo1a.id, results[0].try(:repository).try(:id))
        assert_dogstats_increment(1, "security_center.access_violation", tags: ["feature:secret_scanning", "scope:organization"])
      end

      test "only rows belonging to the repo are returned" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        get_tokens_response = ResponseMock.new(
          data: GitHub::Proto::SecretScanning::Api::V2::GetTokensResponse.new(
            tokens: [
              GitHub::Proto::SecretScanning::Api::V2::Token.new(
                created_at: Time.parse("2021-05-05"),
                first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(path: "path/to/file.rb"),
                id: 1,
                label: "Amazon AWS Secret Access Key",
                repository_id: @repo1a.id,
                number: 1
              ),
              GitHub::Proto::SecretScanning::Api::V2::Token.new(
                created_at: Time.parse("2021-05-05"),
                first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(path: "path/to/file.rb"),
                id: 2,
                label: "Amazon AWS Secret Access Key",
                repository_id: @repo1b.id,
                number: 1
              ),
            ]
          )
        )

        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).returns(get_tokens_response)

        results, _ = AlertQueryService.for_repository(repository: @repo1a, current_user: @user).get_alerts

        assert_equal(1, results.count)
        assert_equal(@repo1a.id, results[0]&.repository.id)
        assert_dogstats_increment(1, "security_center.access_violation", tags: ["feature:secret_scanning", "scope:repository"])
      end
    end

    context ".get_filter_options" do
      test "handles nil response" do
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once

        sut = AlertQueryService.for_repository(repository: @repo1a, current_user: @user)
        result = sut.get_filter_options(filter: "secret-type")

        options, error = result
        assert_empty options
        assert error
      end

      test "handles unknown filter type" do
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).never

        sut = AlertQueryService.for_repository(repository: @repo1a, current_user: @user)
        result = sut.get_filter_options(filter: "foo")

        options, error = result
        assert_empty options
        assert error
      end

      test "maps secret type filter options" do
        SecretScanning::Features::Business::CustomPatterns.any_instance.stubs(:feature_available?).returns(true)
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).times(3).returns(get_token_group_by_counts_response)
        options, error = AlertQueryService.for_business(business: @business, organizations: @business.organizations, current_user: @user, user_session: @user_session).get_filter_options(filter: "secret-type")

        expected = [
          {
            title: "Service providers",
            items: [
              {
                count: 156,
                label: "type_1",
                slug: "type_1",
                type_value: "type_1"
              }
            ],
          },
          {
            title: "Custom patterns",
            items: [],
          }
        ]
        refute error
        assert_equal expected, options

        # assert count for open
        options, error = AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: "is:open", current_user: @user, user_session: @user_session).get_filter_options(filter: "secret-type")
        assert_equal 72, options.dig(0, :items, 0, :count)

        # assert count for closed
        options, error = AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: "is:closed", current_user: @user, user_session: @user_session).get_filter_options(filter: "secret-type")
        assert_equal 84, options.dig(0, :items, 0, :count)
      end

      test "omits custom pattern secret type filter options when feature is not available" do
        SecretScanning::Features::Business::CustomPatterns.any_instance.stubs(:feature_available?).returns(false)
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).times(3).returns(get_token_group_by_counts_response)
        options, error = AlertQueryService.for_business(business: @business, organizations: @business.organizations, current_user: @user, user_session: @user_session).get_filter_options(filter: "secret-type")

        expected = [
          {
            title: "Service providers",
            items: [
              {
                count: 156,
                label: "type_1",
                slug: "type_1",
                type_value: "type_1"
              }
            ],
          },
        ]
        refute error
        assert_equal expected, options

        # assert count for open
        options, error = AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: "is:open", current_user: @user, user_session: @user_session).get_filter_options(filter: "secret-type")
        assert_equal 72, options.dig(0, :items, 0, :count)

        # assert count for closed
        options, error = AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: "is:closed", current_user: @user, user_session: @user_session).get_filter_options(filter: "secret-type")
        assert_equal 84, options.dig(0, :items, 0, :count)
      end

      test "maps provider filter options" do
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).times(3).returns(get_token_group_by_counts_response)
        options, error = AlertQueryService.for_business(business: @business, organizations: @business.organizations, current_user: @user, user_session: @user_session).get_filter_options(filter: "provider")

        expected = [
          {
            items: [
              {
                count: 99,
                label: "AWS",
                description: "AWS",
                slug: "aws"
              },
              {
                count: 9,
                label: "GitHub",
                description: "GitHub",
                slug: "github"
              },
              {
                count: 3,
                label: "GitHub Secret Scanning",
                description: "GitHub Secret Scanning",
                slug: "github_secret_scanning"
              }
            ]
          }
        ]
        refute error
        assert_equal expected, options

        # assert count for open
        options, error = AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: "is:open", current_user: @user, user_session: @user_session).get_filter_options(filter: "provider")
        assert_equal 44, options.dig(0, :items, 0, :count)

        # assert count for closed
        options, error = AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: "is:closed", current_user: @user, user_session: @user_session).get_filter_options(filter: "provider")
        assert_equal 55, options.dig(0, :items, 0, :count)
      end

      test "maps repository filter options" do
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).times(3).returns(get_token_group_by_counts_response)
        options, error = AlertQueryService.for_organization(organization: @org1, current_user: @user, user_session: @user_session).get_filter_options(filter: "repo")

        expected = [
          {
            items: [
              {
                count: 55,
                label: "repo1b",
                slug: "repo1b"
              },
              {
                count: 5,
                label: "repo1a",
                slug: "repo1a"
              }
            ]
          }
        ]
        refute error
        assert_equal expected, options

        # assert count for open
        options, error = AlertQueryService.for_organization(organization: @org1, query: "is:open", current_user: @user, user_session: @user_session).get_filter_options(filter: "repo")
        assert_equal 22, options.dig(0, :items, 0, :count)

        # assert count for closed
        options, error = AlertQueryService.for_organization(organization: @org1, query: "is:closed", current_user: @user, user_session: @user_session).get_filter_options(filter: "repo")
        assert_equal 33, options.dig(0, :items, 0, :count)
      end

      test "maps repository filter options with nwo" do
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).times(3).returns(get_token_group_by_counts_response)
        options, error = AlertQueryService.for_business(business: @business, organizations: @business.organizations, current_user: @user, user_session: @user_session).get_filter_options(filter: "repo")

        expected = [
          {
            items: [
              {
                count: 55,
                label: "repo1b",
                description: "Org1",
                slug: "org1/repo1b"
              },
              {
                count: 5,
                label: "repo1a",
                description: "Org1",
                slug: "org1/repo1a"
              }
            ]
          }
        ]
        refute error
        assert_equal expected, options

        # assert count for open
        options, error = AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: "is:open", current_user: @user, user_session: @user_session).get_filter_options(filter: "repo")
        assert_equal 22, options.dig(0, :items, 0, :count)

        # assert count for closed
        options, error = AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: "is:closed", current_user: @user, user_session: @user_session).get_filter_options(filter: "repo")
        assert_equal 33, options.dig(0, :items, 0, :count)
      end

      test "maps organization filter options" do
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).times(3).returns(get_token_group_by_counts_response)
        options, error = AlertQueryService.for_business(business: @business, organizations: @business.organizations, current_user: @user, user_session: @user_session).get_filter_options(filter: "owner")

        expected = [
          {
            items: [
              {
                count: 60,
                description: "Organization",
                label: "Org1",
                slug: "org1",
              }
            ]
          }
        ]
        refute error
        assert_equal expected, options

        # assert count for open
        options, error = AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: "is:open", current_user: @user, user_session: @user_session).get_filter_options(filter: "owner")
        assert_equal 24, options.dig(0, :items, 0, :count)

        # assert count for closed
        options, error = AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: "is:closed", current_user: @user, user_session: @user_session).get_filter_options(filter: "owner")
        assert_equal 36, options.dig(0, :items, 0, :count)
      end

      test "maps owner filter options", skip_enterprise: true do
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).times(3).returns(get_token_group_by_counts_response_for_emus)
        options, error = AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, current_user: @emu_owner, user_session: @user_session).get_filter_options(filter: "owner")
        expected = [
          {
            items: [
              {
                count: 55,
                description: "User",
                label: @emu_user2.display_login,
                slug: @emu_user2.display_login.downcase,
              },
              {
                count: 5,
                description: "User",
                label: @emu_user1.display_login,
                slug: @emu_user1.display_login.downcase,
              },
            ]
          }
        ]

        refute error
        assert_equal expected, options

        # assert count for open
        options, error = AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: "is:open", current_user: @emu_owner, user_session: @user_session).get_filter_options(filter: "owner")
        assert_equal 22, options.dig(0, :items, 0, :count)
        assert_equal 2, options.dig(0, :items, 1, :count)

        # assert count for closed
        options, error = AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: "is:closed", current_user: @emu_owner, user_session: @user_session).get_filter_options(filter: "owner")
        assert_equal 33, options.dig(0, :items, 0, :count)
        assert_equal 3, options.dig(0, :items, 1, :count)
      end
    end

    context ".get_filter_options - business selector" do
      test "adds selector to request" do
        expected_user_filter = GitHub.enterprise? || TestEnv.test_with_all_emus? ? :ALL : :NONE
        expected = {
          business_selector: {
            organization_ids: @business.organizations.map(&:id),
            repository_ids: [],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ],
            id: @business.id,
            user_ids: [],
            user_filter: expected_user_filter,
            owner_types: [],
            excluded_owner_types: [],
          }
        }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entry(expected))
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, current_user: @user, user_session: @user_session).get_filter_options(filter: "secret-type")
      end

      test "owner filter - single include" do
        expected = {
          business_selector: {
            organization_ids: [@org1.id],
            repository_ids: [],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ],
            id: @business.id,
            user_ids: [],
            user_filter: :NONE,
            owner_types: [],
            excluded_owner_types: [],
          }
        }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entry(expected))

        query = "owner:#{@org1.name}"
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_filter_options(filter: "secret-type")
      end

      test "owner filter - single exclude" do
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once
          .with { |params| params[:business_selector][:organization_ids].include? @org1.id }
          .with { |params| params[:business_selector][:organization_ids].include? @org3.id }
          .with { |params| params[:business_selector][:organization_ids].exclude? @org2.id }

        query = "-owner:#{@org2.name}"
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_filter_options(filter: "secret-type")
      end

      test "owner filter - single conflict" do
        query = "owner:#{@org3.name} -owner:#{@org3.name}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).never
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_filter_options(filter: "secret-type")
      end

      test "owner filter - conflict with include" do
        expected = {
          business_selector: {
            organization_ids: [@org2.id],
            repository_ids: [],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ],
            id: @business.id,
            user_ids: [],
            user_filter: :NONE,
            owner_types: [],
            excluded_owner_types: [],
          }
        }

        query = "owner:#{@org1.name},#{@org2.name} -owner:#{@org1.name}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entry(expected))
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_filter_options(filter: "secret-type")
      end

      test "owner filter - conflict with exclude" do
        query = "owner:#{@org1.name} -owner:#{@org1.name},#{@org2.name}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).never
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_filter_options(filter: "secret-type")
      end

      test "owner filter - ignored for org aggregation" do
        expected = {
          business_selector: {
            organization_ids: @business.organizations.map(&:id), # NOTE org query filter ignored
            repository_ids: [],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ],
            id: @business.id,
            user_ids: [],
            user_filter: (GitHub.enterprise? || TestEnv.test_with_all_emus?) ? :ALL : :NONE,
            owner_types: [],
            excluded_owner_types: [],
          }
        }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entry(expected))

        query = "owner:#{@org1.name}"
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_filter_options(filter: "owner")
      end

      context "owner filter", skip_enterprise: true do
        test "single include" do
          expected = {
            business_selector: {
              organization_ids: [],
              repository_ids: [],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @emu_biz.id,
              user_ids: [@emu_user1.id],
              user_filter: :ONLY,
              owner_types: [],
            excluded_owner_types: [],
            }
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entry(expected))

          query = "owner:#{@emu_user1.name}"
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_filter_options(filter: "secret-type")
        end

        test "single exclude" do
          expected = {
            business_selector: {
              organization_ids: @emu_biz.organizations.map(&:id),
              repository_ids: [],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @emu_biz.id,
              user_ids: [@emu_user1.id],
              user_filter: :EXCEPT,
              owner_types: [],
            excluded_owner_types: [],
            }
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entry(expected))

          query = "-owner:#{@emu_user1.name}"
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_filter_options(filter: "secret-type")
        end

        test "single conflict" do
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).never

          query = "owner:#{@emu_user1.name} -owner:#{@emu_user1.name}"
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_filter_options(filter: "secret-type")
        end

        test "conflict include" do
          expected = {
            business_selector: {
              organization_ids: [],
              repository_ids: [],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @emu_biz.id,
              user_ids: [@emu_user1.id],
              user_filter: :ONLY,
              owner_types: [],
            excluded_owner_types: [],
            }
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entry(expected))

          query = "owner:#{@emu_user1.name},#{@emu_user2.name} -owner:#{@emu_user2.name}"
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_filter_options(filter: "secret-type")
        end

        test "conflict with exclude" do
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).never

          query = "owner:#{@emu_user1.name} owner:#{@emu_user1.name},#{@emu_user2.name}"
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_filter_options(filter: "secret-type")
        end

        test "ignored for owner aggregation" do
          expected = {
            # NOTE user filters not applied
            business_selector: {
              organization_ids: @emu_biz.organizations.map(&:id),
              repository_ids: [],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @emu_biz.id,

              user_ids: [],
              user_filter: :ALL,
              owner_types: [],
              excluded_owner_types: [],
            }
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entry(expected))

          query = "owner:#{@emu_user1.name}"
          AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: @emu_owner, user_session: @user_session).get_filter_options(filter: "owner")
        end

        context "when the current user is not a business owner" do
          test "returns results from current user" do
            rando = create(:emu, business: @emu_biz)
            expected = {
              business_selector: {
                organization_ids: [],
                repository_ids: [],
                repos_are_excluded: false,
                repository_visibilities: [
                  :REPOSITORY_VISIBILITY_PUBLIC,
                  :REPOSITORY_VISIBILITY_PRIVATE,
                  :REPOSITORY_VISIBILITY_INTERNAL
                ],
                id: @emu_biz.id,
                user_ids: [rando.id],
                user_filter: :ONLY,
                owner_types: [],
                excluded_owner_types: [],
              }
            }
            GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entry(expected))

            AlertQueryService.for_business(business: @emu_biz, organizations: [], current_user: rando, user_session: @user_session).get_filter_options(filter: "secret-type")
          end

          test "user aggregation still filters to current user" do
            rando = create(:emu, business: @emu_biz)
            expected = {
              business_selector: {
                organization_ids: @emu_biz.organizations.map(&:id),
                repository_ids: [],
                repos_are_excluded: false,
                repository_visibilities: [
                  :REPOSITORY_VISIBILITY_PUBLIC,
                  :REPOSITORY_VISIBILITY_PRIVATE,
                  :REPOSITORY_VISIBILITY_INTERNAL
                ],
                id: @emu_biz.id,

                # NOTE user filters ARE applied because current user is not an owner of the business
                user_ids: [rando.id],
                user_filter: :ONLY,
                owner_types: [],
                excluded_owner_types: [],
              }
            }
            GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entry(expected))

            query = "owner:#{@emu_user1.name}"
            AlertQueryService.for_business(business: @emu_biz, organizations: @emu_biz.organizations, query: query, current_user: rando, user_session: @user_session).get_filter_options(filter: "owner")
          end
        end
      end

      test "repo filter - single include" do
        expected_user_filter = GitHub.enterprise? || TestEnv.test_with_all_emus? ? :ALL : :NONE
        expected = {
          business_selector: {
            organization_ids: @business.organizations.map(&:id),
            repository_ids: [@repo1a.id],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ],
            id: @business.id,
            user_ids: [],
            user_filter: expected_user_filter,
            owner_types: [],
            excluded_owner_types: [],
          }
        }

        query = "repo:#{@repo1a.nwo}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entry(expected))
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_filter_options(filter: "secret-type")
      end

      test "repo filter - single exclude" do
        expected_user_filter = GitHub.enterprise? || TestEnv.test_with_all_emus? ? :ALL : :NONE
        expected = {
          business_selector: {
            organization_ids: @business.organizations.map(&:id),
            repository_ids: [@repo1a.id],
            repos_are_excluded: true,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ],
            id: @business.id,
            user_ids: [],
            user_filter: expected_user_filter,
            owner_types: [],
            excluded_owner_types: [],
          }
        }

        query = "-repo:#{@repo1a.nwo}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entry(expected))
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_filter_options(filter: "secret-type")
      end

      test "repo filter - single conflict" do
        query = "repo:#{@repo1a.nwo} -repo:#{@repo1a.nwo}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).never
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_filter_options(filter: "secret-type")
      end

      test "repo filter - conflict with include" do
        expected_user_filter = GitHub.enterprise? || TestEnv.test_with_all_emus? ? :ALL : :NONE
        expected = {
          business_selector: {
            organization_ids: @business.organizations.map(&:id),
            repository_ids: [@repo1b.id],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ],
            id: @business.id,
            user_ids: [],
            user_filter: expected_user_filter,
            owner_types: [],
            excluded_owner_types: [],
          }
        }

        query = "repo:#{@repo1a.nwo},#{@repo1b.nwo} -repo:#{@repo1a.nwo}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entry(expected))
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_filter_options(filter: "secret-type")
      end

      test "repo filter - conflict with exclude" do
        query = "repo:#{@repo1a.nwo} -repo:#{@repo1a.nwo},#{@repo1c.nwo}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).never
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_filter_options(filter: "secret-type")
      end

      test "repo filter - ignored for repo aggregation" do
        expected_user_filter = GitHub.enterprise? || TestEnv.test_with_all_emus? ? :ALL : :NONE
        expected = {
          business_selector: {
            organization_ids: @business.organizations.map(&:id),
            repository_ids: [], # NOTE repo query filter ignored
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ],
            id: @business.id,
            user_ids: [],
            user_filter: expected_user_filter,
            owner_types: [],
            excluded_owner_types: [],
          }
        }

        query = "repo:#{@repo1a.nwo}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entry(expected))
        AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_filter_options(filter: "repo")
      end

      ::SecretScanningControllerHelper::GroupByAggregation::TO_SERVICE_ENUM.keys.each do |aggregation|
        test "team filter - single include - #{aggregation} aggregation" do
          ::SecurityCenter::FeatureFlagHelper.stubs(:business_secret_scanning_teams_filter_enabled?).returns(true)
          expected = {
            business_selector: {
              organization_ids: @business.organizations.map(&:id),
              repository_ids: [@repo1a.id],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @business.id,
              user_ids: [],
              user_filter: (GitHub.enterprise? || TestEnv.test_with_all_emus?) ? :ALL : :NONE,
              owner_types: [],
              excluded_owner_types: [],
            }
          }

          query = "team:#{@team1a.combined_slug}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entry(expected))
          AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_filter_options(filter: aggregation)
        end
      end

      ::SecretScanningControllerHelper::GroupByAggregation::TO_SERVICE_ENUM.keys.each do |aggregation|
        test "topic filter - single include - #{aggregation} aggregation" do
          ::SecurityCenter::FeatureFlagHelper.stubs(:business_secret_scanning_topic_filter_enabled?).returns(true)
          expected = {
            business_selector: {
              organization_ids: @business.organizations.map(&:id),
              repository_ids: [@repo1a.id],
              repos_are_excluded: false,
              repository_visibilities: [
                :REPOSITORY_VISIBILITY_PUBLIC,
                :REPOSITORY_VISIBILITY_PRIVATE,
                :REPOSITORY_VISIBILITY_INTERNAL
              ],
              id: @business.id,
              user_ids: [],
              user_filter: (GitHub.enterprise? || TestEnv.test_with_all_emus?) ? :ALL : :NONE,
              owner_types: [],
              excluded_owner_types: [],
            }
          }

          query = "topic:#{@topica.name}"
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entry(expected))
          AlertQueryService.for_business(business: @business, organizations: @business.organizations, query: query, current_user: @user, user_session: @user_session).get_filter_options(filter: aggregation)
        end
      end
    end

    context ".get_filter_options - org selector" do
      test "adds selector to request" do
        expected = {
          org_selector: {
            owner_id: @org1.id,
            repository_ids: [],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ]
          }
        }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entry(expected))
        AlertQueryService.for_organization(organization: @org1, current_user: @user, user_session: @user_session).get_filter_options(filter: "secret-type")
      end

      test "repo filter - single include" do
        expected = {
          org_selector: {
            owner_id: @org1.id,
            repository_ids: [@repo1a.id],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ]
          }
        }

        query = "repo:#{@repo1a.name}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entry(expected))
        AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_filter_options(filter: "secret-type")
      end

      test "repo filter - single exclude" do
        expected = {
          org_selector: {
            owner_id: @org1.id,
            repository_ids: [@repo1a.id],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ]
          }
        }

        query = "repo:#{@repo1a.name}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entry(expected))
        AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_filter_options(filter: "secret-type")
      end

      test "repo filter - single conflict" do
        query = "repo:#{@repo1a.name} -repo:#{@repo1a.name}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).never
        AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_filter_options(filter: "secret-type")
      end

      test "repo filter - conflict with include" do
        expected = {
          org_selector: {
            owner_id: @org1.id,
            repository_ids: [@repo1b.id],
            repos_are_excluded: false,
            repository_visibilities: [
              :REPOSITORY_VISIBILITY_PUBLIC,
              :REPOSITORY_VISIBILITY_PRIVATE,
              :REPOSITORY_VISIBILITY_INTERNAL
            ]
          }
        }

        query = "repo:#{@repo1a.name},#{@repo1b.name} -repo:#{@repo1a.name}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entry(expected))
        AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_filter_options(filter: "secret-type")
      end

      test "repo filter - conflict with exclude" do
        query = "repo:#{@repo1a.name} -repo:#{@repo1a.name},#{@repo1c.name}"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).never
        AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_filter_options(filter: "secret-type")
      end

      test "ignores repo filter for repo aggregation" do
        query = "repo:#{@repo1a.name}"
        expected = {
          org_selector: has_entries({
            repository_ids: [],
            repos_are_excluded: false,
          })
        }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entries(expected))
        AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_filter_options(filter: "repo")
      end

      ::SecretScanningControllerHelper::GroupByAggregation::TO_SERVICE_ENUM.keys.each do |aggregation|
        next if aggregation == ::SecretScanningControllerHelper::GroupByAggregation::OWNER # Not supported for `for_organization`
        test "team filter - single include - #{aggregation} aggregation" do
          # Team filter uses repo IDs under-the-hood just like the repo name filter,
          # so this test makes sure that only the repo name part of the filtering is ignored.
          query = "team:#{@team1a.slug}"
          expected = {
            org_selector: has_entries({
              repository_ids: [@repo1a.id],
              repos_are_excluded: false,
            })
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entries(expected))
          AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_filter_options(filter: aggregation)
        end
      end

      ::SecretScanningControllerHelper::GroupByAggregation::TO_SERVICE_ENUM.keys.each do |aggregation|
        next if aggregation == ::SecretScanningControllerHelper::GroupByAggregation::OWNER # Not supported for `for_organization`
        test "topic filter - single include - #{aggregation} aggregation" do
          # Topic filter uses repo IDs under-the-hood just like the repo name filter,
          # so this test makes sure that only the repo name part of the filtering is ignored.
          query = "topic:#{@topica.name}"
          expected = {
            org_selector: has_entries({
              repository_ids: [@repo1a.id],
              repos_are_excluded: false,
            })
          }
          GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entries(expected))
          AlertQueryService.for_organization(organization: @org1, query: query, current_user: @user, user_session: @user_session).get_filter_options(filter: aggregation)
        end
      end
    end

    context ".get_filter_options - repo selector" do
      test "adds selector to request" do
        expected = {
          repo_selector: {
            repository_id: @repo1a.id
          }
        }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entry(expected))
        AlertQueryService.for_repository(repository: @repo1a, current_user: @user).get_filter_options(filter: "secret-type")
      end
    end

    context ".get_filter_options - state" do
      test "no filter" do
        query = ""
        expected = { token_state: :NO_STATE }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entry(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_filter_options(filter: "secret-type")
      end

      test "explicit open" do
        query = "is:open"
        expected = { token_state: :OPEN }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entry(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_filter_options(filter: "secret-type")
      end

      test "explicit closed" do
        query = "is:closed"
        expected = { token_state: :RESOLVED }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entry(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_filter_options(filter: "secret-type")
      end

      test "invalid value" do
        query = "is:foobar"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).never
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_filter_options(filter: "secret-type")
      end
    end

    context ".get_filter_options - secret type filter" do
      test "no filter" do
        query = ""
        expected = { token_slugs: [], exclude_token_slugs: [] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_filter_options(filter: "provider")
      end

      test "single include" do
        query = "secret-type:abc"
        expected = { token_slugs: ["abc"], exclude_token_slugs: [] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_filter_options(filter: "provider")
      end

      test "single exclude" do
        query = "-secret-type:def"
        expected = { token_slugs: [], exclude_token_slugs: ["def"] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_filter_options(filter: "provider")
      end

      test "conflict" do
        query = "secret-type:abc -secret-type:abc"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).never
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_filter_options(filter: "provider")
      end

      test "conflict with include" do
        query = "secret-type:abc,def -secret-type:abc"
        expected = { token_slugs: ["def"], exclude_token_slugs: [] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_filter_options(filter: "provider")
      end

      test "conflict with exclude" do
        query = "secret-type:abc -secret-type:abc,def"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).never
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_filter_options(filter: "provider")
      end

      test "ignored for secret-type aggregation" do
        query = "secret-type:abc"
        expected = { token_slugs: [], exclude_token_slugs: [] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_filter_options(filter: "secret-type")
      end
    end

    context ".get_filter_options - provider filter" do
      test "no filter" do
        query = ""
        expected = { token_providers: [], exclude_token_providers: [] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_filter_options(filter: "secret-type")
      end

      test "single include" do
        query = "provider:abc"
        expected = { token_providers: ["abc"], exclude_token_providers: [] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_filter_options(filter: "secret-type")
      end

      test "single exclude" do
        query = "-provider:def"
        expected = { token_providers: [], exclude_token_providers: ["def"] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_filter_options(filter: "secret-type")
      end

      test "conflict" do
        query = "provider:abc -provider:abc"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).never
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_filter_options(filter: "secret-type")
      end

      test "conflict with include" do
        query = "provider:abc,def -provider:abc"
        expected = { token_providers: ["def"], exclude_token_providers: [] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_filter_options(filter: "secret-type")
      end

      test "conflict with exclude" do
        query = "provider:abc -provider:abc,def"
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).never
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_filter_options(filter: "secret-type")
      end

      test "ignored for provider aggregation" do
        query = "provider:abc"
        expected = { token_providers: [], exclude_token_providers: [] }
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_token_group_by_counts).once.with(has_entries(expected))
        AlertQueryService.for_repository(repository: @repo1a, query: query, current_user: @user).get_filter_options(filter: "provider")
      end
    end

    context ".get_alerts - raw secret" do
      test "sets raw secret from encrypted secret" do
        response = ResponseMock.new(
          data: GitHub::Proto::SecretScanning::Api::V2::GetTokensResponse.new(
            tokens: [
              GitHub::Proto::SecretScanning::Api::V2::Token.new(
                created_at: Time.parse("2021-05-05"),
                first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(path: "path/to/file.rb"),
                id: 1,
                label: "Amazon AWS Secret Access Key",
                repository_id: @repo1a.id,
                number: 1,
                encrypted_token: "encrypted_content"
              )
            ]
          )
        )
        SecretScanning::Features::Business::CustomPatterns.any_instance.stubs(:feature_available?).returns(true)
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).times(1).returns(response)
        SecretScanning::Encryption::EncryptedSecretsCryptoHelper.expects(:decrypt_encrypted_secret).once.returns("decrypted_raw_secret")

        alerts, open_alert_count, closed_alert_count, service_response, request_error = AlertQueryService.for_repository(repository: @repo1a, query: "is:open", current_user: @user).get_alerts(page: 1, per_page: 25)
        assert_equal "decrypted_raw_secret", alerts[0]&.raw_secret
      end

      test "does not raw secret from blobs as a fallback" do
        response = ResponseMock.new(
          data: GitHub::Proto::SecretScanning::Api::V2::GetTokensResponse.new(
            tokens: [
              GitHub::Proto::SecretScanning::Api::V2::Token.new(
                created_at: Time.parse("2021-05-05"),
                first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(
                  path: "path/to/file.rb",
                  start_line: 1,
                  blob_oid: "123",
                ),
                id: 1,
                label: "Amazon AWS Secret Access Key",
                repository_id: @repo1a.id,
                number: 1,
                encrypted_token: nil,
              )
            ]
          )
        )
        GitHub::TokenScanning::Service::Client.any_instance.expects(:get_tokens).times(1).returns(response)
        AlertQueryService.any_instance.expects(:fetch_blobs).never

        AlertQueryService.for_repository(repository: @repo1a, query: "is:open", current_user: @user).get_alerts(page: 1, per_page: 25)
      end
    end

    private

    def get_tokens_response
      ResponseMock.new(
        data: GitHub::Proto::SecretScanning::Api::V2::GetTokensResponse.new(
          tokens: [
            GitHub::Proto::SecretScanning::Api::V2::Token.new(
              created_at: Time.parse("2021-05-05"),
              first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(path: "path/to/file.rb"),
              id: 1,
              label: "Amazon AWS Secret Access Key",
              repository_id: @repo1a.id,
              number: 1
            ),
            GitHub::Proto::SecretScanning::Api::V2::Token.new(
              created_at: Time.parse("2021-05-05"),
              first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(path: "path/to/file.rb"),
              id: 2,
              label: "Amazon AWS Secret Access Key",
              repository_id: @repo1b.id,
              number: 1
            ),
            GitHub::Proto::SecretScanning::Api::V2::Token.new(
              created_at: Time.parse("2021-06-05"),
              first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(path: "path/to/file.rb"),
              id: 3,
              label: "Amazon AWS Secret Access Key",
              repository_id: @repo1a.id,
              number: 1
            )
          ]
        )
      )
    end

    def get_token_group_by_counts_response
      ResponseMock.new(
        data: GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse.new(
          counts: [
            GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount.new(
              repo_aggregation: GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::RepoTokenCountAggregation.new(
                counts: [
                  GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::RepoTokenCountAggregation::RepoCount.new(
                    repository_id: @repo1a.id,
                    unresolved_count: 2,
                    resolved_count: 3
                  ),
                  GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::RepoTokenCountAggregation::RepoCount.new(
                    repository_id: @repo1b.id,
                    unresolved_count: 22,
                    resolved_count: 33
                  ),
                ]
              )
            ),
            GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount.new(
              provider_aggregation: GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::ProviderTokenCountAggregation.new(
                counts: [
                  GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::ProviderTokenCountAggregation::ProviderCount.new(
                    provider_name: "GitHub",
                    unresolved_count: 4,
                    resolved_count: 5
                  ),
                  GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::ProviderTokenCountAggregation::ProviderCount.new(
                    provider_name: "AWS",
                    unresolved_count: 44,
                    resolved_count: 55
                  ),
                  GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::ProviderTokenCountAggregation::ProviderCount.new(
                    provider_name: "GitHub Secret Scanning",
                    unresolved_count: 1,
                    resolved_count: 2
                  ),
                ]
              )
            ),
            GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount.new(
              type_aggregation: GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::SecretTypeTokenCountAggregation.new(
                counts: [
                  GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::SecretTypeTokenCountAggregation::TypeCount.new(
                    type: GitHub::Proto::SecretScanning::Api::V2::TokenType.new(
                      type_value:  "type_1",
                      label_value: "type_1",
                      slug_value:  "type_1",
                    ),
                    unresolved_count: 6,
                    resolved_count: 7
                  ),
                  GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::SecretTypeTokenCountAggregation::TypeCount.new(
                    type: GitHub::Proto::SecretScanning::Api::V2::TokenType.new(
                      type_value:  "type_1_v2",
                      label_value: "type_1",
                      slug_value:  "type_1",
                    ),
                    unresolved_count: 66,
                    resolved_count: 77
                  )
                ]
              )
            )
          ]
        )
      )
    end

    def get_token_group_by_counts_response_for_emus
      ResponseMock.new(
        data: GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse.new(
          counts: [
            GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount.new(
              repo_aggregation: GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::RepoTokenCountAggregation.new(
                counts: [
                  GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::RepoTokenCountAggregation::RepoCount.new(
                    repository_id: @emu_repo1.id,
                    unresolved_count: 2,
                    resolved_count: 3
                  ),
                  GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::RepoTokenCountAggregation::RepoCount.new(
                    repository_id: @emu_repo2.id,
                    unresolved_count: 22,
                    resolved_count: 33
                  ),
                ]
              )
            ),
            GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount.new(
              provider_aggregation: GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::ProviderTokenCountAggregation.new(
                counts: [
                  GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::ProviderTokenCountAggregation::ProviderCount.new(
                    provider_name: "GitHub",
                    unresolved_count: 4,
                    resolved_count: 5
                  ),
                  GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::ProviderTokenCountAggregation::ProviderCount.new(
                    provider_name: "AWS",
                    unresolved_count: 44,
                    resolved_count: 55
                  ),
                ]
              )
            ),
            GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount.new(
              type_aggregation: GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::SecretTypeTokenCountAggregation.new(
                counts: [
                  GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::SecretTypeTokenCountAggregation::TypeCount.new(
                    type: GitHub::Proto::SecretScanning::Api::V2::TokenType.new(
                      type_value:  "type_1",
                      label_value: "type_1",
                      slug_value:  "type_1",
                    ),
                    unresolved_count: 6,
                    resolved_count: 7
                  ),
                  GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::SecretTypeTokenCountAggregation::TypeCount.new(
                    type: GitHub::Proto::SecretScanning::Api::V2::TokenType.new(
                      type_value:  "type_1_v2",
                      label_value: "type_1",
                      slug_value:  "type_1",
                    ),
                    unresolved_count: 66,
                    resolved_count: 77
                  )
                ]
              )
            )
          ]
        )
      )
    end
  end
end
