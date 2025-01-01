# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class Initialization
    module Repositories
      class FeatureEnablementJobTest < GitHub::TestCase
        include JobTestHelper

        fixtures do
          @biz = create(:business)

          @org = create(:organization, business: @biz)
          @org_repo = create(:repository, owner: @org)

          @user = create(:user)
          @user_repo = create(:repository, owner: @user, force_user_owned: true)
        end

        setup do
          ::Repository.any_instance.stubs(:code_scanning_auto_codeql_security_center_status)
            .returns(::Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("not_eligible", 0))
        end

        context "when the repository is org-owned" do
          test "it creates a feature revision" do
            assert_changes(
              -> { ::SecurityOverviewAnalytics::FeatureStatusRevision.count },
              from: 0,
              to: 1,
            ) do
              perform_enqueued_jobs(only: Repositories::FeatureEnablementJob) do
                Repositories::FeatureEnablementJob.perform_later(repository_id: @org_repo.id)
              end
            end
          end

          context "when a feature revision already exists for the repository" do
            test "it doesn't get enqueued" do
              create(
                :security_overview_analytics_feature_status_revision,
                date_id: ::SecurityOverviewAnalytics::Date.id_from_time(Time.now),
                repository_id: @org_repo.id
              )

              assert_no_changes(
                -> { ::SecurityOverviewAnalytics::FeatureStatusRevision.count }
              ) do
                perform_enqueued_jobs(only: Repositories::FeatureEnablementJob) do
                  Repositories::FeatureEnablementJob.perform_later(repository_id: @org_repo.id)
                end
              end

              assert_no_enqueued_jobs(only: Repositories::FeatureEnablementJob)
            end

            test "it clears the lock" do
              create(
                :security_overview_analytics_feature_status_revision,
                date_id: ::SecurityOverviewAnalytics::Date.id_from_time(Time.now),
                repository_id: @org_repo.id
              )

              Repositories::FeatureEnablementJob.perform_later(repository_id: @org_repo.id)
              job = Repositories::FeatureEnablementJob.new(repository_id: @org_repo.id)
              refute job.locked?
            end
          end
        end

        context "when the repository is user-owned" do
          context "when a feature revision does not already exist for the repository" do
            if TestEnv.test_with_all_emus?
              context "when the owner is an EMU" do
                test "it creates a feature revision" do
                  ::AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.expects(:security_center_for_emus_enabled?).returns(true)

                  assert_changes(
                    -> { ::SecurityOverviewAnalytics::FeatureStatusRevision.count },
                    from: 0,
                    to: 1,
                  ) do
                    perform_enqueued_jobs(only: Repositories::FeatureEnablementJob) do
                      Repositories::FeatureEnablementJob.perform_later(repository_id: @user_repo.id)
                    end
                  end
                end
              end
            end

            context "when the owner is not an EMU", skip_with_all_emus: true do
              context "in dotcom", skip_enterprise: true do
                test "it does not create a feature revision" do
                  ::AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(true)

                  assert_no_changes(
                    -> { ::SecurityOverviewAnalytics::FeatureStatusRevision.count },
                    from: 0,
                  ) do
                    perform_enqueued_jobs(only: Repositories::FeatureEnablementJob) do
                      Repositories::FeatureEnablementJob.perform_later(repository_id: @user_repo.id)
                    end
                  end
                end
              end

              context "in GHES", enterprise_only: true do
                context "when EMUs are not enabled for security center" do
                  test "it creates a row if advanced security is available to users" do
                    ::AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.expects(:feature_available?).at_least_once.returns(true)

                    assert_changes(
                      -> { ::SecurityOverviewAnalytics::FeatureStatusRevision.count },
                      from: 0,
                      to: 1,
                    ) do
                      perform_enqueued_jobs(only: Repositories::FeatureEnablementJob) do
                        Repositories::FeatureEnablementJob.perform_later(repository_id: @user_repo.id)
                      end
                    end
                  end

                  test "it does not create a row if advanced security is unavailable to users" do
                    ::AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.expects(:feature_available?).at_least_once.returns(false)

                    assert_no_changes(
                      -> { ::SecurityOverviewAnalytics::FeatureStatusRevision.count },
                      from: 0,
                    ) do
                      perform_enqueued_jobs(only: Repositories::FeatureEnablementJob) do
                        Repositories::FeatureEnablementJob.perform_later(repository_id: @user_repo.id)
                      end
                    end
                  end
                end
              end
            end
          end

          context "when a feature revision already exists for the repository" do
            test "it doesn't get enqueued" do
              create(
                :security_overview_analytics_feature_status_revision,
                date_id: ::SecurityOverviewAnalytics::Date.id_from_time(Time.now),
                repository_id: @user_repo.id
              )

              assert_no_changes(
                -> { ::SecurityOverviewAnalytics::FeatureStatusRevision.count }
              ) do
                perform_enqueued_jobs(only: Repositories::FeatureEnablementJob) do
                  Repositories::FeatureEnablementJob.perform_later(repository_id: @user_repo.id)
                end
              end

              assert_no_enqueued_jobs(only: Repositories::FeatureEnablementJob)
            end

            test "it clears the lock" do
              create(
                :security_overview_analytics_feature_status_revision,
                date_id: ::SecurityOverviewAnalytics::Date.id_from_time(Time.now),
                repository_id: @user_repo.id
              )

              Repositories::FeatureEnablementJob.perform_later(repository_id: @user_repo.id)
              job = Repositories::FeatureEnablementJob.new(repository_id: @user_repo.id)
              refute job.locked?
            end
          end
        end

        context "resiliency" do
          test "retries on standard conditions" do
            assert_retry_conditions(job: FeatureEnablementJob, args: [{ repository_id: @org_repo.id }])
          end

          test "retries on transient errors" do
            FeatureEnablementJob::RETRYABLE_EXCEPTIONS.each do |error|
              assert_retry_on_error(
                error,
                FeatureEnablementJob,
                [{ repository_id: @org_repo.id }],
                true,
              )
            end
          end
        end
      end
    end
  end
end
