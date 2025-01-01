# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class Initialization
    module Repositories
      class RepoMetadataJobTest < GitHub::TestCase
        include JobTestHelper

        fixtures do
          @biz = create(:business)

          @org = create(:organization, business: @biz)
          @org_repo = create(:repository, owner: @org)

          @user = create(:user)
          @user_repo = create(:repository, owner: @user, force_user_owned: true)
        end

        context "when the repository is org-owned" do
          context "when a row in table soa_repositories does not exist for the repository" do
            test "it creates a row" do
              assert_changes(
                -> { ::SecurityOverviewAnalytics::Repository.count },
                from: 0,
                to: 1
              ) do
                perform_enqueued_jobs(only: Repositories::RepoMetadataJob) do
                  Repositories::RepoMetadataJob.perform_later(repository_id: @org_repo.id)
                end
              end

              row = ::SecurityOverviewAnalytics::Repository.first
              assert_equal @org_repo.id, T.must(row).repository_id
              assert_equal @org_repo.owner_id, T.must(row).organization_id
              assert_equal @org_repo.owner_id, T.must(row).owner_id
              assert_equal @biz.id, T.must(row).business_id
              assert_equal "ORGANIZATION", T.must(row).owner_type
            end
          end

          context "when a row in table soa_repositories exists for the repository" do
            test "it doesn't get enqueued" do
              soa_repo = create(:security_overview_analytics_repository, repository: @org_repo)

              assert_no_changes(
                -> { soa_repo.reload.updated_at },
              ) do
                perform_enqueued_jobs(only: Repositories::RepoMetadataJob) do
                  Repositories::RepoMetadataJob.perform_later(repository_id: @org_repo.id)
                end
              end

              assert_no_enqueued_jobs(only: Repositories::RepoMetadataJob)
            end

            test "it clears the lock" do
              soa_repo = create(:security_overview_analytics_repository, repository: @org_repo)

              Repositories::RepoMetadataJob.perform_later(repository_id: @org_repo.id)
              job = Repositories::RepoMetadataJob.new(repository_id: @org_repo.id)
              refute job.locked?
            end
          end
        end

        context "when the repository is user-owned" do
          context "when a row in table soa_repositories does not exist for the repository" do
            if TestEnv.test_with_all_emus?
              context "when the owner is an EMU" do
                test "it creates a row" do
                  ::AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.expects(:security_center_for_emus_enabled?).returns(true)

                  assert_changes(
                    -> { ::SecurityOverviewAnalytics::Repository.count },
                    from: 0,
                    to: 1
                  ) do
                    perform_enqueued_jobs(only: Repositories::RepoMetadataJob) do
                      Repositories::RepoMetadataJob.perform_later(repository_id: @user_repo.id)
                    end
                  end

                  row = ::SecurityOverviewAnalytics::Repository.first
                  assert_equal @user_repo.id, T.must(row).repository_id
                  assert_equal 0, T.must(row).organization_id
                  assert_equal @user_repo.owner_id, T.must(row).owner_id
                  assert_equal @biz.id, T.must(row).business_id
                  assert_equal "USER", T.must(row).owner_type
                end
              end
            end

            context "when the owner is not an EMU", skip_with_all_emus: true do
              context "in dotcom", skip_enterprise: true do
                test "it does not create a row" do
                  assert_no_changes(
                    -> { ::SecurityOverviewAnalytics::Repository.count },
                    from: 0,
                  ) do
                    perform_enqueued_jobs(only: Repositories::RepoMetadataJob) do
                      Repositories::RepoMetadataJob.perform_later(repository_id: @user_repo.id)
                    end
                  end
                end
              end

              context "in GHES", enterprise_only: true do
                test "it creates a row if advanced security is available to users" do
                  ::AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.expects(:feature_available?).at_least_once.returns(true)

                  assert_changes(
                    -> { ::SecurityOverviewAnalytics::Repository.count },
                    from: 0,
                    to: 1,
                  ) do
                    perform_enqueued_jobs(only: Repositories::RepoMetadataJob) do
                      Repositories::RepoMetadataJob.perform_later(repository_id: @user_repo.id)
                    end
                  end
                end

                test "it does not create a row if advanced security is unavailable to users" do
                  ::AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.expects(:feature_available?).at_least_once.returns(false)

                  assert_no_changes(
                    -> { ::SecurityOverviewAnalytics::Repository.count },
                    from: 0,
                  ) do
                    perform_enqueued_jobs(only: Repositories::RepoMetadataJob) do
                      Repositories::RepoMetadataJob.perform_later(repository_id: @user_repo.id)
                    end
                  end
                end
              end
            end
          end

          context "when a row in table soa_repositories exists for the repository" do
            test "it doesn't get enqueued" do
              soa_repo = create(:security_overview_analytics_repository, repository: @user_repo)

              assert_no_changes(
                -> { soa_repo.reload.updated_at },
              ) do
                perform_enqueued_jobs(only: Repositories::RepoMetadataJob) do
                  Repositories::RepoMetadataJob.perform_later(repository_id: @user_repo.id)
                end
              end

              assert_no_enqueued_jobs(only: Repositories::RepoMetadataJob)
            end

            test "it clears the lock" do
              soa_repo = create(:security_overview_analytics_repository, repository: @user_repo)

              Repositories::RepoMetadataJob.perform_later(repository_id: @user_repo.id)
              job = Repositories::RepoMetadataJob.new(repository_id: @user_repo.id)
              refute job.locked?
            end
          end
        end
      end
    end
  end
end
