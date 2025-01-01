# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  module Fanout
    class RepositoryOwnerJobTest < GitHub::TestCase
      include DogstatsTestHelpers
      include JobTestHelper

      fixtures do
        if GitHub.enterprise?
          @biz = create(:global_business)
          @user = create(:user)
        else
          @biz = create(:business, :enterprise_managed)
          @user = create(:emu, business: @biz)
        end
        @org = create(:organization, business: @biz)
        @org_repo = create(:repository, owner: @org, admin: @user)
        @another_org_repo = create(:repository, owner: @org, admin: @user)
        @user_repo = create(:repository, owner: @user)
        @another_user_repo = create(:repository, owner: @user)

        on_multi_tenant_enterprise do
          @mt_user = create(:emu)
          @mt_business = @mt_user.enterprise_managed_business
          @mt_org = create :enterprise_linked_organization, :with_org_namespacing, business: @mt_business, admin: @mt_user
          @mt_org_repo = create(:private_repository, owner: @mt_org, admin: @mt_user)
          @mt_emu_repo = create(:private_repository, owner: @mt_user)
        end
      end

      setup do
        # Stubs for tenant validation
        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)
      end

      context "organization tenant scope" do
        context "#perform with Action::Initialize" do
          test "does not perform if provided features already initialized" do
            Types::Feature.values.each do |feature|
              Session.new(
                action: Types::Action::Initialize,
                tenant_scope: Types::TenantScope::Organization,
                tenant_id: @org.id,
                feature:
              ).lock!
            end

            RepositoryOwnerJob.any_instance.expects(:perform).never

            RepositoryOwnerJob.perform_now(
              tenant_scope: Types::TenantScope::Organization.serialize,
              tenant_id: @org.id,
              action: Types::Action::Initialize.serialize
            )

            assert_dogstats_increment 1, "security_overview_analytics.tenant_fanout.stopped", tags: ["reason:features_already_initialized"]
            refute_dogstats_increment "security_overview_analytics.tenant_fanout.processed"
          end

          test "enqueues pull request alerts initialization job" do
            RepositoryOwnerJob.stub_const(:BATCH_SIZE, 1) do
              perform_enqueued_jobs only: [RepositoryOwnerJob] do
                RepositoryOwnerJob.perform_now(
                  tenant_scope: Types::TenantScope::Organization.serialize,
                  tenant_id: @org.id,
                  action: Types::Action::Initialize.serialize
                )
              end
            end

            assert_enqueued_with(
              job: Initialization::CodeScanningPullRequestAlertsJob,
              args: [{ repository_id: @org_repo.id, last_session_locked_at: nil }]
            )
            assert_enqueued_with(
              job: Initialization::CodeScanningPullRequestAlertsJob,
              args: [{ repository_id: @another_org_repo.id, last_session_locked_at: nil }]
            )

            Types::Feature.values.each do |feature|
              assert Session.new(
                action: Types::Action::Initialize,
                tenant_scope: Types::TenantScope::Organization,
                tenant_id: @org.id,
                feature:
              ).locked?
            end

            assert_dogstats_distribution 1, "batched_job.total_time.dist"
            assert_dogstats_increment 3, "security_overview_analytics.tenant_fanout.processed"
            refute_dogstats_increment "security_overview_analytics.tenant_fanout.stopped"
          end
        end

        context "#perform with Action::Reconcile" do
          test "does not perform if provided features not initialized" do
            RepositoryOwnerJob.any_instance.expects(:perform).never

            RepositoryOwnerJob.perform_now(
              tenant_scope: Types::TenantScope::Organization.serialize,
              tenant_id: @org.id,
              action: Types::Action::Reconcile.serialize
            )

            assert_dogstats_increment 1, "security_overview_analytics.tenant_fanout.stopped", tags: ["reason:features_not_initialized"]
            refute_dogstats_increment "security_overview_analytics.tenant_fanout.processed"
          end

          test "does not perform if provided features recently reconciled" do
            Types::Feature.values.each do |feature|
              Session.new(
                action: Types::Action::Initialize,
                tenant_scope: Types::TenantScope::Organization,
                tenant_id: @org.id,
                feature:
              ).lock!
            end
            Types::Feature.values.each do |feature|
              Session.new(
                action: Types::Action::Reconcile,
                tenant_scope: Types::TenantScope::Organization,
                tenant_id: @org.id,
                feature:
              ).lock!
            end

            RepositoryOwnerJob.any_instance.expects(:perform).never

            RepositoryOwnerJob.perform_now(
              tenant_scope: Types::TenantScope::Organization.serialize,
              tenant_id: @org.id,
              action: Types::Action::Reconcile.serialize
            )

            assert_dogstats_increment 1, "security_overview_analytics.tenant_fanout.stopped", tags: ["reason:features_reconciled_recently"]
            refute_dogstats_increment "security_overview_analytics.tenant_fanout.processed"
          end

          test "enqueues pull request alerts initialization job" do
            last_session_locked_at = 14.days.ago.iso8601(3).to_time.utc
            Types::Feature.values.each do |feature|
              Session.new(
                action: Types::Action::Initialize,
                tenant_scope: Types::TenantScope::Organization,
                tenant_id: @org.id,
                feature:
              ).lock!
            end
            Types::Feature.values.each do |feature|
              Session.new(
                action: Types::Action::Reconcile,
                tenant_scope: Types::TenantScope::Organization,
                tenant_id: @org.id,
                feature:
              ).lock!(at: last_session_locked_at)
            end

            RepositoryOwnerJob.stub_const(:BATCH_SIZE, 1) do
              perform_enqueued_jobs only: [RepositoryOwnerJob] do
                RepositoryOwnerJob.perform_now(
                  tenant_scope: Types::TenantScope::Organization.serialize,
                  tenant_id: @org.id,
                  action: Types::Action::Reconcile.serialize
                )
              end
            end

            Types::Feature.values.each do |feature|
              assert Session.new(
                action: Types::Action::Reconcile,
                tenant_scope: Types::TenantScope::Organization,
                tenant_id: @org.id,
                feature:
              ).locked?
            end

            assert_enqueued_with(
              job: Reconciliation::CodeScanningPullRequestAlertsJob,
              args: [{ repository_id: @org_repo.id, last_session_locked_at: last_session_locked_at }]
            )
            assert_enqueued_with(
              job: Reconciliation::CodeScanningPullRequestAlertsJob,
              args: [{ repository_id: @another_org_repo.id, last_session_locked_at: last_session_locked_at }]
            )

            assert_dogstats_distribution 1, "batched_job.total_time.dist"
            assert_dogstats_increment 3, "security_overview_analytics.tenant_fanout.processed"
            refute_dogstats_increment "security_overview_analytics.tenant_fanout.stopped"
          end
        end

        context "input validations" do
          test "tenant_scope is required" do
            assert_no_enqueued_jobs(only: RepositoryOwnerJob) do
              assert_raises_with_message(ArgumentError, "Invalid tenant_scope input.") do
                RepositoryOwnerJob.perform_later(
                  tenant_id: @org.id,
                  action: Types::Action::Initialize.serialize
                )
              end
            end
            refute RepositoryOwnerJob.new.locked?
          end

          test "business scope in not allowed" do
            assert_no_enqueued_jobs(only: RepositoryOwnerJob) do
              assert_raises_with_message(ArgumentError, "Invalid tenant_scope input.") do
                RepositoryOwnerJob.perform_later(
                  tenant_scope: Types::TenantScope::Business.serialize,
                  tenant_id: @biz.id,
                  action: Types::Action::Initialize.serialize
                )
              end
            end
            refute RepositoryOwnerJob.new.locked?
          end

          test "tenant_scope should match enum value" do
            assert_no_enqueued_jobs(only: RepositoryOwnerJob) do
              assert_raises_with_message(ArgumentError, "Invalid tenant_scope input.") do
                RepositoryOwnerJob.perform_later(
                  tenant_scope: "RandomScope",
                  tenant_id: @org.id,
                  action: Types::Action::Initialize.serialize
                )
              end
            end
            refute RepositoryOwnerJob.new.locked?
          end

          test "tenant_id is required" do
            assert_no_enqueued_jobs(only: RepositoryOwnerJob) do
              assert_raises_with_message(ArgumentError, "Invalid tenant_id input.") do
                RepositoryOwnerJob.perform_later(
                  tenant_scope: Types::TenantScope::Organization.serialize,
                  action: Types::Action::Initialize.serialize
                )
              end
            end
            refute RepositoryOwnerJob.new.locked?
          end

          test "action is required" do
            assert_no_enqueued_jobs(only: RepositoryOwnerJob) do
              assert_raises_with_message(ArgumentError, "Invalid action input.") do
                RepositoryOwnerJob.perform_later(
                  tenant_scope: Types::TenantScope::Organization.serialize,
                  tenant_id: @org.id
                )
              end
            end
            refute RepositoryOwnerJob.new.locked?
          end

          test "action input should match enum value" do
            assert_no_enqueued_jobs(only: RepositoryOwnerJob) do
              assert_raises_with_message(ArgumentError, "Invalid action input.") do
                RepositoryOwnerJob.perform_later(
                  tenant_scope: Types::TenantScope::Organization.serialize,
                  tenant_id: @org.id,
                  action: "RandomAction"
                )
              end
            end
            refute RepositoryOwnerJob.new.locked?
          end

          test "features input should match enum value" do
            assert_no_enqueued_jobs(only: RepositoryOwnerJob) do
              assert_raises_with_message(ArgumentError, "Invalid features input.") do
                RepositoryOwnerJob.perform_later(
                  tenant_scope: Types::TenantScope::Organization.serialize,
                  tenant_id: @org.id,
                  action: Types::Action::Initialize.serialize,
                  features: ["RandomFeature"]
                )
              end
            end
            refute RepositoryOwnerJob.new.locked?
          end

          test "stops if tenant not found" do
            RepositoryOwnerJob.any_instance.expects(:perform).never

            RepositoryOwnerJob.perform_now(
              tenant_scope: Types::TenantScope::Organization.serialize,
              tenant_id: 99999999,
              action: Types::Action::Initialize.serialize
            )

            assert_dogstats_increment 1, "security_overview_analytics.tenant_fanout.stopped", tags: ["reason:tenant_not_found"]
            refute_dogstats_increment "security_overview_analytics.tenant_fanout.processed"
          end

          context "initialize action" do
            test "requires tenant to be in scope" do
              TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)

              RepositoryOwnerJob.any_instance.expects(:perform).never

              RepositoryOwnerJob.perform_now(
                tenant_scope: Types::TenantScope::Organization.serialize,
                tenant_id: @org.id,
                action: Types::Action::Initialize.serialize
              )

              assert_dogstats_increment 1, "security_overview_analytics.tenant_fanout.stopped", tags: ["reason:owner_not_in_scope"]
              refute_dogstats_increment "security_overview_analytics.tenant_fanout.processed"
            end
          end

          context "reconcile action" do
            test "requires tenant to be in scope" do
              TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)

              RepositoryOwnerJob.any_instance.expects(:perform).never

              RepositoryOwnerJob.perform_now(
                tenant_scope: Types::TenantScope::Organization.serialize,
                tenant_id: @org.id,
                action: Types::Action::Reconcile.serialize
              )

              assert_dogstats_increment 1, "security_overview_analytics.tenant_fanout.stopped", tags: ["reason:owner_not_in_scope"]
              refute_dogstats_increment "security_overview_analytics.tenant_fanout.processed"
            end
          end
        end

        context "on multi tenant enterprise" do
          test "sets the tenant context to the correct business" do
            on_multi_tenant_enterprise do
              ::Business.expects(:find_by).with(id: @mt_business.id).returns(@mt_business).once
              RepositoryOwnerJob.perform_now(
                tenant_scope: Types::TenantScope::Organization.serialize,
                tenant_id: @mt_org.id,
                action: Types::Action::Initialize.serialize
              )
            end
          end
        end
      end

      context "user tenant scope" do
        context "#perform with Action::Initialize" do
          test "does not perform if provided features already initialized" do
            Types::Feature.values.each do |feature|
              Session.new(
                action: Types::Action::Initialize,
                tenant_scope: Types::TenantScope::User,
                tenant_id: @org.id,
                feature:
              ).lock!
            end

            RepositoryOwnerJob.any_instance.expects(:perform).never

            RepositoryOwnerJob.perform_now(
              tenant_scope: Types::TenantScope::User.serialize,
              tenant_id: @org.id,
              action: Types::Action::Initialize.serialize
            )

            assert_dogstats_increment 1, "security_overview_analytics.tenant_fanout.stopped", tags: ["reason:features_already_initialized"]
            refute_dogstats_increment "security_overview_analytics.tenant_fanout.processed"
          end

          test "does not enqueues pull request alerts initialization job" do
            assert_no_enqueued_jobs only: Initialization::CodeScanningPullRequestAlertsJob do
              perform_enqueued_jobs only: [RepositoryOwnerJob] do
                RepositoryOwnerJob.perform_now(
                  tenant_scope: Types::TenantScope::User.serialize,
                  tenant_id: @user.id,
                  action: Types::Action::Initialize.serialize
                )
              end
            end

            refute Session.new(
              action: Types::Action::Initialize,
              tenant_scope: Types::TenantScope::User,
              tenant_id: @org.id,
              feature: Types::Feature::CodeScanningPullRequestAlert
            ).locked?
          end
        end

        context "#perform with Action::Reconcile" do
          test "does not perform if provided features not initialized" do
            RepositoryOwnerJob.any_instance.expects(:perform).never

            RepositoryOwnerJob.perform_now(
              tenant_scope: Types::TenantScope::User.serialize,
              tenant_id: @user.id,
              action: Types::Action::Reconcile.serialize
            )

            assert_dogstats_increment 1, "security_overview_analytics.tenant_fanout.stopped", tags: ["reason:features_not_initialized"]
            refute_dogstats_increment "security_overview_analytics.tenant_fanout.processed"
          end

          test "does not enqueues pull request alerts reconciliation job" do
            Types::Feature.values.each do |feature|
              Session.new(
                action: Types::Action::Initialize,
                tenant_scope: Types::TenantScope::Organization,
                tenant_id: @org.id,
                feature:
              ).lock!
            end

            assert_no_enqueued_jobs only: Reconciliation::CodeScanningPullRequestAlertsJob do
              RepositoryOwnerJob.perform_now(
                tenant_scope: Types::TenantScope::User.serialize,
                tenant_id: @user.id,
                action: Types::Action::Reconcile.serialize
              )
            end

            refute Session.new(
              action: Types::Action::Reconcile,
              tenant_scope: Types::TenantScope::User,
              tenant_id: @org.id,
              feature: Types::Feature::CodeScanningPullRequestAlert
            ).locked?
          end
        end

        context "input validations" do
          test "tenant_scope is required" do
            assert_no_enqueued_jobs(only: RepositoryOwnerJob) do
              assert_raises_with_message(ArgumentError, "Invalid tenant_scope input.") do
                RepositoryOwnerJob.perform_later(
                  tenant_id: @user.id,
                  action: Types::Action::Initialize.serialize
                )
              end
            end
            refute RepositoryOwnerJob.new.locked?
          end

          test "business scope in not allowed" do
            assert_no_enqueued_jobs(only: RepositoryOwnerJob) do
              assert_raises_with_message(ArgumentError, "Invalid tenant_scope input.") do
                RepositoryOwnerJob.perform_later(
                  tenant_scope: Types::TenantScope::Business.serialize,
                  tenant_id: @biz.id,
                  action: Types::Action::Initialize.serialize
                )
              end
            end
            refute RepositoryOwnerJob.new.locked?
          end

          test "tenant_scope should match enum value" do
            assert_no_enqueued_jobs(only: RepositoryOwnerJob) do
              assert_raises_with_message(ArgumentError, "Invalid tenant_scope input.") do
                RepositoryOwnerJob.perform_later(
                  tenant_scope: "RandomScope",
                  tenant_id: @user.id,
                  action: Types::Action::Initialize.serialize
                )
              end
            end
            refute RepositoryOwnerJob.new.locked?
          end

          test "tenant_id is required" do
            assert_no_enqueued_jobs(only: RepositoryOwnerJob) do
              assert_raises_with_message(ArgumentError, "Invalid tenant_id input.") do
                RepositoryOwnerJob.perform_later(
                  tenant_scope: Types::TenantScope::User.serialize,
                  action: Types::Action::Initialize.serialize
                )
              end
            end
            refute RepositoryOwnerJob.new.locked?
          end

          test "action is required" do
            assert_no_enqueued_jobs(only: RepositoryOwnerJob) do
              assert_raises_with_message(ArgumentError, "Invalid action input.") do
                RepositoryOwnerJob.perform_later(
                  tenant_scope: Types::TenantScope::User.serialize,
                  tenant_id: @user.id
                )
              end
            end
            refute RepositoryOwnerJob.new.locked?
          end

          test "action input should match enum value" do
            assert_no_enqueued_jobs(only: RepositoryOwnerJob) do
              assert_raises_with_message(ArgumentError, "Invalid action input.") do
                RepositoryOwnerJob.perform_later(
                  tenant_scope: Types::TenantScope::User.serialize,
                  tenant_id: @user.id,
                  action: "RandomAction"
                )
              end
            end
            refute RepositoryOwnerJob.new.locked?
          end

          test "features input should match enum value" do
            assert_no_enqueued_jobs(only: RepositoryOwnerJob) do
              assert_raises_with_message(ArgumentError, "Invalid features input.") do
                RepositoryOwnerJob.perform_later(
                  tenant_scope: Types::TenantScope::User.serialize,
                  tenant_id: @user.id,
                  action: Types::Action::Initialize.serialize,
                  features: ["RandomFeature"]
                )
              end
            end
            refute RepositoryOwnerJob.new.locked?
          end

          test "stops if tenant not found" do
            RepositoryOwnerJob.any_instance.expects(:perform).never

            RepositoryOwnerJob.perform_now(
              tenant_scope: Types::TenantScope::User.serialize,
              tenant_id: 99999999,
              action: Types::Action::Initialize.serialize
            )

            assert_dogstats_increment 1, "security_overview_analytics.tenant_fanout.stopped", tags: ["reason:tenant_not_found"]
            refute_dogstats_increment "security_overview_analytics.tenant_fanout.processed"
          end

          context "initialize action" do
            test "requires tenant to be in scope" do
              TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)

              RepositoryOwnerJob.any_instance.expects(:perform).never

              RepositoryOwnerJob.perform_now(
                tenant_scope: Types::TenantScope::User.serialize,
                tenant_id: @org.id,
                action: Types::Action::Initialize.serialize
              )

              assert_dogstats_increment 1, "security_overview_analytics.tenant_fanout.stopped", tags: ["reason:owner_not_in_scope"]
              refute_dogstats_increment "security_overview_analytics.tenant_fanout.processed"
            end
          end

          context "reconcile action" do
            test "requires tenant to be in scope" do
              TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)

              RepositoryOwnerJob.any_instance.expects(:perform).never

              RepositoryOwnerJob.perform_now(
                tenant_scope: Types::TenantScope::User.serialize,
                tenant_id: @user.id,
                action: Types::Action::Reconcile.serialize
              )

              assert_dogstats_increment 1, "security_overview_analytics.tenant_fanout.stopped", tags: ["reason:owner_not_in_scope"]
              refute_dogstats_increment "security_overview_analytics.tenant_fanout.processed"
            end
          end
        end

        context "on multi tenant enterprise" do
          test "sets the tenant context to the correct business" do
            on_multi_tenant_enterprise do
              ::Business.expects(:find_by).with(id: @mt_business.id).returns(@mt_business).once
              RepositoryOwnerJob.perform_now(
                tenant_scope: Types::TenantScope::User.serialize,
                tenant_id: @mt_user.id,
                action: Types::Action::Initialize.serialize
              )
            end
          end
        end
      end

      context "resiliency" do
        test "it retries on standard conditions" do
          assert_retry_conditions(
            job: RepositoryOwnerJob,
            args: [
              tenant_scope: Types::TenantScope::Organization.serialize,
              tenant_id: @org.id,
              action: Types::Action::Initialize.serialize
            ],
            using_kwargs: true
          )
        end
      end

      context "hash lock" do
        test "does not allow concurrent jobs for the same pull request" do
          assert_enqueued_jobs 1, only: RepositoryOwnerJob do
            RepositoryOwnerJob.perform_later(
              tenant_scope: Types::TenantScope::Organization.serialize,
              tenant_id: @org.id,
              action: Types::Action::Initialize.serialize
            )
            RepositoryOwnerJob.perform_later(
              tenant_scope: Types::TenantScope::Organization.serialize,
              tenant_id: @org.id,
              action: Types::Action::Initialize.serialize,
              features: ["test"]
            )
            RepositoryOwnerJob.perform_later(
              tenant_scope: Types::TenantScope::Organization.serialize,
              tenant_id: @org.id,
              action: Types::Action::Initialize.serialize,
              features: [Types::Feature::CodeScanningPullRequestAlert.serialize]
            )
          end
        end
      end
    end
  end
end
