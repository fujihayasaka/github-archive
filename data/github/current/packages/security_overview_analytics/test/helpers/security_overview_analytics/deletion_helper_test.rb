# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class DeletionHelperTest < GitHub::TestCase

    fixtures do
      @dates = [
        create(:security_overview_analytics_date, date_value: Time.parse("2023-09-17")),
        create(:security_overview_analytics_date, date_value: Time.parse("2023-09-14")), # simulate gap
        create(:security_overview_analytics_date, date_value: Time.parse("2023-09-13")),
      ]

      ############################## Business 1.

      @biz_1 = create(:business)
      @biz_1_org_1 = create(:organization, business: @biz_1)
      @biz_1_org_2 = create(:organization, business: @biz_1)
      @biz_1_org_1_repo_1 = create(:private_repository, owner: @biz_1_org_1)
      @biz_1_org_1_soa_repo_1 = create(:security_overview_analytics_repository, repository: @biz_1_org_1_repo_1)
      create(:soa_feature_status, repository_metadata: @biz_1_org_1_soa_repo_1)

      # Create a revision of each type for each date
      @dates.reduce(Date::FUTURE_DATE_ID) do |next_date_id, date|
        create(
          :security_overview_analytics_dependabot_alert_revision,
          alert_number: 1,
          date: date,
          next_revision_date_id: next_date_id,
          repository_metadata: @biz_1_org_1_soa_repo_1,
        )
        create(
          :security_overview_analytics_code_scanning_alert_revision,
          date: date,
          next_revision_date_id: next_date_id,
          repository_metadata: @biz_1_org_1_soa_repo_1,
        )
        create(
          :security_overview_analytics_secret_scanning_alert_revision,
          date: date,
          next_revision_date_id: next_date_id,
          repository_metadata: @biz_1_org_1_soa_repo_1,
        )
        create(
          :security_overview_analytics_feature_status_revision,
          date: date,
          next_revision_date_id: next_date_id,
          repository_metadata: @biz_1_org_1_soa_repo_1,
        )
        next date.id
      end

      unless GitHub.enterprise?
        ############################## Business 2.

        @biz_2 = create(:business)
        @biz_2_org_1 = create(:organization, business: @biz_2)
        @biz_2_org_2 = create(:organization, business: @biz_2)
        @biz_2_org_1_repo_1 = create(:private_repository, owner: @biz_2_org_1)
        @biz_2_org_1_soa_repo_1 = create(:security_overview_analytics_repository, repository: @biz_2_org_1_repo_1)
        create(:soa_feature_status, repository_metadata: @biz_2_org_1_soa_repo_1)

        # Create a revision of each type for each date
        @dates.reduce(Date::FUTURE_DATE_ID) do |next_date_id, date|
          create(
            :security_overview_analytics_dependabot_alert_revision,
            alert_number: 1,
            date: date,
            next_revision_date_id: next_date_id,
            repository_metadata: @biz_2_org_1_soa_repo_1,
          )
          create(
            :security_overview_analytics_code_scanning_alert_revision,
            date: date,
            next_revision_date_id: next_date_id,
            repository_metadata: @biz_2_org_1_soa_repo_1,
          )
          create(
            :security_overview_analytics_secret_scanning_alert_revision,
            date: date,
            next_revision_date_id: next_date_id,
            repository_metadata: @biz_2_org_1_soa_repo_1,
          )
          create(
            :security_overview_analytics_feature_status_revision,
            date: date,
            next_revision_date_id: next_date_id,
            repository_metadata: @biz_2_org_1_soa_repo_1,
          )
          next date.id
        end
      end
    end

    setup do
      @mi_for_biz_1 = Initialization.for(@biz_1)
      @mi_for_biz_1.set_all_to_initialized
      @mi_for_biz_1_org_1 = Initialization.for(@biz_1_org_1)
      @mi_for_biz_1_org_1.set_all_to_initialized
      @mi_for_biz_1_org_2 = Initialization.for(@biz_1_org_2)
      @mi_for_biz_1_org_2.set_all_to_initialized

      unless GitHub.enterprise?
        @mi_for_biz_2 = Initialization.for(@biz_2)
        @mi_for_biz_2.set_all_to_initialized
        @mi_for_biz_2_org_1 = Initialization.for(@biz_2_org_1)
        @mi_for_biz_2_org_1.set_all_to_initialized
        @mi_for_biz_2_org_2 = Initialization.for(@biz_2_org_2)
        @mi_for_biz_2_org_2.set_all_to_initialized
      end
    end

    context ".delete_all_for_businesses", skip_enterprise: true do
      test "it deletes all biz-level KV entries for the provided businesses" do
        assert_changes(
          -> { @mi_for_biz_1.all_initialized? },
          from: true,
          to: false
        ) do
          DeletionHelper.delete_all_for_businesses(business_ids: [@biz_1.id])
        end

        assert(@mi_for_biz_2.all_initialized?)
      end

      test "it deletes all data for the provided business' orgs" do
        DeletionHelper.expects(:delete_all_for_organizations).with(organization_ids: @biz_1.organizations.pluck(:id), type: nil)
        DeletionHelper.delete_all_for_businesses(business_ids: [@biz_1.id])
      end

      # validating type-specific reset
      Initialization::ScopeStrategy::Business.available_initialization_types.each do |type|
        context "when limiting to #{type.serialize}" do
          test "it deletes the KV entry for the provided businesses" do
            @mi_for_biz_1.set_all_to_initialized
            assert @mi_for_biz_1.all_initialized?

            DeletionHelper.delete_all_for_businesses(business_ids: [@biz_1.id], type:)

            refute @mi_for_biz_1.initialized?(type:)
            # verify all other types remain initialized
            Initialization::ScopeStrategy::Business.available_initialization_types.reject { |other_type| other_type == type }.each do |other_type|
              assert @mi_for_biz_1.initialized?(type: other_type)
            end
          end

          test "it deletes all data for the provided business' orgs" do
            DeletionHelper.expects(:delete_all_for_organizations).with(organization_ids: @biz_1.organizations.pluck(:id), type:)
            DeletionHelper.delete_all_for_businesses(business_ids: [@biz_1.id], type:)
          end
        end
      end
    end

    context ".delete_all_for_organizations", skip_enterprise: true do
      test "it deletes all KV entries for the provided organizations" do
        assert_changes(
          -> { @mi_for_biz_1_org_1.all_initialized? },
          from: true,
          to: false
        ) do
          DeletionHelper.delete_all_for_organizations(organization_ids: [@biz_1_org_1.id])
        end

        # Assert data for other orgs are unaffected.
        assert(@mi_for_biz_1_org_2.all_initialized?)
        assert(@mi_for_biz_2_org_1.all_initialized?)
        assert(@mi_for_biz_2_org_2.all_initialized?)
      end

      test "it deletes Dependabot alert revisions for the provided organizations" do
        assert_changes(
          -> do
            ::SecurityOverviewAnalytics::DependabotAlertRevision
              .includes(:repository_metadata)
              .where(repository_metadata: { organization_id: [@biz_1_org_1.id] })
              .size
          end,
          from: @dates.length,
          to: 0
        ) do
          DeletionHelper.delete_all_for_organizations(organization_ids: [@biz_1_org_1.id])
        end

        # Assert data for other orgs are unaffected.
        assert(::SecurityOverviewAnalytics::DependabotAlertRevision.count > 0)
      end

      test "it deletes code scanning alert revisions for the provided organizations" do
        assert_changes(
          -> do
            ::SecurityOverviewAnalytics::CodeScanningAlertRevision
              .includes(:repository_metadata)
              .where(repository_metadata: { organization_id: [@biz_1_org_1.id] })
              .size
          end,
          from: @dates.length,
          to: 0
        ) do
          DeletionHelper.delete_all_for_organizations(organization_ids: [@biz_1_org_1.id])
        end

        # Assert data for other orgs are unaffected.
        assert(::SecurityOverviewAnalytics::CodeScanningAlertRevision.count > 0)
      end

      test "it deletes secret scanning alert revisions for the provided organizations" do
        assert_changes(
          -> do
            ::SecurityOverviewAnalytics::SecretScanningAlertRevision
              .includes(:repository_metadata)
              .where(repository_metadata: { organization_id: [@biz_1_org_1.id] })
              .size
          end,
          from: @dates.length,
          to: 0
        ) do
          DeletionHelper.delete_all_for_organizations(organization_ids: [@biz_1_org_1.id])
        end

        # Assert data for other orgs are unaffected.
        assert(::SecurityOverviewAnalytics::SecretScanningAlertRevision.count > 0)
      end

      test "it deletes feature status revisions for the provided organizations" do
        assert_changes(
          -> do
            ::SecurityOverviewAnalytics::FeatureStatusRevision
              .includes(:repository_metadata)
              .where(repository_metadata: { organization_id: [@biz_1_org_1.id] })
              .size
          end,
          from: @dates.length,
          to: 0
        ) do
          DeletionHelper.delete_all_for_organizations(organization_ids: [@biz_1_org_1.id])
        end

        # Assert data for other orgs are unaffected.
        assert(::SecurityOverviewAnalytics::FeatureStatusRevision.count > 0)
      end

      test "it deletes feature status summary for the provided organizations" do
        assert_changes(
          -> do
            ::SecurityOverviewAnalytics::FeatureStatus
              .includes(:repository_metadata)
              .where(repository_metadata: { organization_id: [@biz_1_org_1.id] })
              .size
          end,
          from: 1,
          to: 0
        ) do
          DeletionHelper.delete_all_for_organizations(organization_ids: [@biz_1_org_1.id])
        end

        # Assert data for other orgs are unaffected.
        assert(::SecurityOverviewAnalytics::FeatureStatus.count > 0)
      end

      test "it deletes repo metadata for the provided organizations" do
        assert_changes(
          -> { ::SecurityOverviewAnalytics::Repository.where(organization_id: [@biz_1_org_1.id]).size },
          from: 1,
          to: 0
        ) do
          DeletionHelper.delete_all_for_organizations(organization_ids: [@biz_1_org_1.id])
        end

        # Assert data for other orgs are unaffected.
        assert(::SecurityOverviewAnalytics::Repository.count > 0)
      end

      # validating type-specific reset
      Initialization::ScopeStrategy::Organization.available_initialization_types.each do |type|
        context "when limiting to #{type.serialize}" do
          test "it deletes the KV entry for the provided organizations" do
            @mi_for_biz_1_org_1.set_all_to_initialized
            assert @mi_for_biz_1_org_1.all_initialized?

            DeletionHelper.delete_all_for_organizations(organization_ids: [@biz_1_org_1.id], type:)

            refute @mi_for_biz_1_org_1.initialized?(type:)
            # verify all other types remain initialized
            Initialization::ScopeStrategy::Organization.available_initialization_types.reject { |other_type| other_type == type }.each do |other_type|
              assert @mi_for_biz_1_org_1.initialized?(type: other_type), "not initialized for #{other_type.serialize}"
            end
          end

          test "it deletes the specified data for the provided organizations" do
            DeletionHelper.delete_all_for_organizations(organization_ids: [@biz_1_org_1.id], type:)

            expected_dependabot_rev_count = @dates.length
            expected_dependabot_rev_count = 0 if type == Initialization::Type::DependabotAlerts
            expected_dependabot_rev_count = 0 if type == Initialization::Type::RepositoryMetadata # cascade delete
            actual_dependabot_rev_count = ::SecurityOverviewAnalytics::DependabotAlertRevision
              .includes(:repository_metadata)
              .where(repository_metadata: { organization_id: [@biz_1_org_1.id] })
              .length
            assert_equal expected_dependabot_rev_count, actual_dependabot_rev_count

            expected_code_scanning_rev_count = @dates.length
            expected_code_scanning_rev_count = 0 if type == Initialization::Type::CodeScanningAlert
            expected_code_scanning_rev_count = 0 if type == Initialization::Type::RepositoryMetadata # cascade delete
            actual_code_scanning_rev_count = ::SecurityOverviewAnalytics::CodeScanningAlertRevision
              .includes(:repository_metadata)
              .where(repository_metadata: { organization_id: [@biz_1_org_1.id] })
              .length
            assert_equal expected_code_scanning_rev_count, actual_code_scanning_rev_count

            expected_secret_scanning_rev_count = @dates.length
            expected_secret_scanning_rev_count = 0 if type == Initialization::Type::SecretScanningAlert
            expected_secret_scanning_rev_count = 0 if type == Initialization::Type::RepositoryMetadata # cascade delete
            actual_secret_scanning_rev_count = ::SecurityOverviewAnalytics::SecretScanningAlertRevision
              .includes(:repository_metadata)
              .where(repository_metadata: { organization_id: [@biz_1_org_1.id] })
              .length
            assert_equal expected_secret_scanning_rev_count, actual_secret_scanning_rev_count

            expected_feature_status_rev_count = @dates.length
            expected_feature_status_rev_count = 0 if type == Initialization::Type::FeatureEnablement
            expected_feature_status_rev_count = 0 if type == Initialization::Type::RepositoryMetadata # cascade delete
            actual_feature_status_rev_count = ::SecurityOverviewAnalytics::FeatureStatusRevision
              .includes(:repository_metadata)
              .where(repository_metadata: { organization_id: [@biz_1_org_1.id] })
              .length
            assert_equal expected_feature_status_rev_count, actual_feature_status_rev_count

            expected_repo_metadata_count = 1
            expected_repo_metadata_count = 0 if type == Initialization::Type::RepositoryMetadata
            actual_repo_metadata_count = ::SecurityOverviewAnalytics::Repository.where(organization_id: [@biz_1_org_1.id]).size
            assert_equal expected_repo_metadata_count, actual_repo_metadata_count
          end
        end
      end
    end
  end
end
