# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class HydroRepositoryCreatedJobTest < GitHub::TestCase
    include GitHub::QueryAssertionTestHelpers
    include HydroMessageJobTestHelpers

    fixtures do
      GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?

      @queue = HydroRepositoryCreatedJob.queue_name
      @schema = "github.repositories.v1.Created"
      @org = create(:organization, skip_enterprise_managed_organization: true)
      @user = create(:user)
    end

    setup do
      TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).returns(true)
    end

    context "#perform" do
      context "when owner is an organization" do
        test "can create data on repo creation" do
          repo = create(:repository, owner: @org)
          message = {
            repository: Hydro::EntitySerializer.repository(repo)
          }
          refute Repository.find_by(repository_id: repo.id)

          assert_query_counts(4) do
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end

          new_record = Repository.find_by(repository_id: repo.id)
          assert new_record
          assert_equal repo.id, new_record&.repository_id
          assert_equal repo.owner_id, new_record&.organization_id
          assert_equal @org.id, new_record&.owner_id
          if GitHub.single_business_environment?
            assert_equal GitHub.global_business.id, new_record&.business_id
          else
            assert_nil new_record&.business_id
          end
          assert_equal repo.name, new_record&.name
          assert_equal repo.visibility, new_record&.visibility
          assert_equal repo.archived?, new_record&.archived
          assert_equal repo.pushed_at, new_record&.pushed_at
        end

        # Orgs in GHES inherently have an enterprise. Skipping for this test which validates repo owners not contained in an enterprise.
        test "can create data with owner ID (omitting business ID) populated on repo creation", skip_enterprise: true do
          repo = create(:repository, owner: @org)
          message = {
            repository: Hydro::EntitySerializer.repository(repo)
          }
          refute Repository.find_by(repository_id: repo.id)

          assert_query_counts(4) do
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end

          new_record = Repository.find_by(repository_id: repo.id)
          assert new_record
          assert_equal repo.id, new_record&.repository_id
          assert_equal repo.owner_id, new_record&.organization_id
          assert_equal repo.owner_id, new_record&.owner_id
          assert_nil new_record&.business_id
          assert_equal "ORGANIZATION", new_record&.owner_type
          assert_equal repo.name, new_record&.name
          assert_equal repo.visibility, new_record&.visibility
          assert_equal repo.archived?, new_record&.archived
          assert_equal repo.pushed_at, new_record&.pushed_at
        end

        test "can create data with owner ID and business ID populated on repo creation" do
          org = create(:business_plus_organization)
          business = create(:global_business, organizations: [org])

          repo = create(:repository, owner: org)
          message = {
            repository: Hydro::EntitySerializer.repository(repo)
          }
          refute Repository.find_by(repository_id: repo.id)

          assert_query_counts(4) do
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end

          new_record = Repository.find_by(repository_id: repo.id)
          assert new_record
          assert_equal repo.id, new_record&.repository_id
          assert_equal repo.owner_id, new_record&.organization_id
          assert_equal repo.owner_id, new_record&.owner_id
          assert_equal repo.business.id, new_record&.business_id
          assert_equal "ORGANIZATION", new_record&.owner_type
          assert_equal repo.name, new_record&.name
          assert_equal repo.visibility, new_record&.visibility
          assert_equal repo.archived?, new_record&.archived
          assert_equal repo.pushed_at, new_record&.pushed_at
        end
      end

      context "when owner is a user" do
        test "can create data on repo creation" do
          repo = create(:repository, owner: @user, force_user_owned: true)
          message = {
            repository: Hydro::EntitySerializer.repository(repo)
          }
          refute Repository.find_by(repository_id: repo.id)

          assert_query_counts(3) do
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end

          new_record = Repository.find_by(repository_id: repo.id)
          assert new_record
          assert_equal repo.id, new_record&.repository_id
          assert_equal 0, new_record&.organization_id
          assert_equal @user.id, new_record&.owner_id
          if GitHub.single_business_environment?
            assert_equal GitHub.global_business.id, new_record&.business_id
          else
            assert_nil new_record&.business_id
          end
          assert_equal "USER", new_record&.owner_type
          assert_equal repo.name, new_record&.name
          assert_equal repo.visibility, new_record&.visibility
          assert_equal repo.archived?, new_record&.archived
          assert_equal repo.pushed_at, new_record&.pushed_at
        end

        # EMUs and users in GHES inherently have an enterprise. Skipping for this test which validates repo owners not contained in an enterprise.
        test "can create data with owner ID (omitting business ID) populated on repo creation", skip_with_all_emus: true, skip_enterprise: true do
          repo = create(:repository, owner: @user)
          message = {
            repository: Hydro::EntitySerializer.repository(repo)
          }
          refute Repository.find_by(repository_id: repo.id)

          assert_query_counts(3) do
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end

          new_record = Repository.find_by(repository_id: repo.id)
          assert new_record
          assert_equal repo.id, new_record&.repository_id
          assert_equal 0, new_record&.organization_id
          assert_equal repo.owner_id, new_record&.owner_id
          assert_nil new_record&.business_id
          assert_equal "USER", new_record&.owner_type
          assert_equal repo.name, new_record&.name
          assert_equal repo.visibility, new_record&.visibility
          assert_equal repo.archived?, new_record&.archived
          assert_equal repo.pushed_at, new_record&.pushed_at
        end

        if TestEnv.test_with_all_emus? || GitHub.enterprise?
          test "can create data with owner ID and business ID populated on repo creation" do
            repo = create(:repository, owner: @user, force_user_owned: true)
            message = {
              repository: Hydro::EntitySerializer.repository(repo)
            }
            refute Repository.find_by(repository_id: repo.id)

            assert_query_counts(TestEnv.test_with_all_emus? ? 5 : 4) do
              perform_hydro_message_job(message, schema: @schema, queue: @queue)
            end

            new_record = Repository.find_by(repository_id: repo.id)
            assert new_record
            assert_equal repo.id, new_record&.repository_id
            assert_equal 0, new_record&.organization_id
            assert_equal repo.owner_id, new_record&.owner_id
            expected_biz = GitHub.enterprise? ? GitHub.global_business : repo.enterprise_managed_business
            assert_equal expected_biz&.id, new_record&.business_id
            assert_equal "USER", new_record&.owner_type
            assert_equal repo.name, new_record&.name
            assert_equal repo.visibility, new_record&.visibility
            assert_equal repo.archived?, new_record&.archived
            assert_equal repo.pushed_at, new_record&.pushed_at
          end
        end
      end

      test "does nothing if repository owner validation fails" do
        TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).returns(false)
        repo = create(:repository, owner: @org)
        message = {
          repository: Hydro::EntitySerializer.repository(repo)
        }

        assert_query_counts(3) do
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end
        refute Repository.find_by(repository_id: repo.id)
      end

      test "does not throw if a record already exists" do
        repo = create(:repository, owner: @org)
        existing_data = create(:security_overview_analytics_repository, repository: repo)
        message = {
          repository: Hydro::EntitySerializer.repository(repo)
        }

        assert_query_counts(4) do
          assert_nothing_raised do
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end
        end

        data_after_job = Repository.find_by(repository_id: existing_data.repository_id)
        assert_equal existing_data, data_after_job
      end
    end
  end
end
