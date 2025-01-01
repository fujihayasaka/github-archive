# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  module Fanout
    class BusinessOwnerJobTest < GitHub::TestCase
      include DogstatsTestHelpers
      include JobTestHelper

      fixtures do
        if GitHub.enterprise?
          @biz = create(:global_business)
          @user = create(:user, business: @biz)
        else
          @biz = create(:business, :enterprise_managed)
          @user = create(:emu, business: @biz)
        end
        @org = create(:organization, business: @biz)
        @another_org = create(:organization, business: @biz)

        on_multi_tenant_enterprise do
          @mt_user = create(:emu)
          @mt_biz = @mt_user.enterprise_managed_business
          @mt_org = create(:enterprise_linked_organization, :with_org_namespacing, business: @mt_biz, admin: @mt_user)
        end
      end

      setup do
        # For EMU
        GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true) if GitHub.enterprise?
        Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
      end

      context "organization owner type" do
        context "#perform with Action::Initialize" do
          test "does not perform if provided features already initialized" do
            Types::Feature.values.each do |feature|
              Session.new(
                action: Types::Action::Initialize,
                tenant_scope: Types::TenantScope::Business,
                tenant_id: @biz.id,
                feature:,
                feature_prerequisite: Types::Owner::Organization
              ).lock!
            end

            BusinessJob.any_instance.expects(:perform).never

            BusinessJob.perform_now(
              tenant_scope: Types::TenantScope::Business.serialize,
              tenant_id: @biz.id,
              owner_type: Types::Owner::Organization.serialize,
              action: Types::Action::Initialize.serialize
            )

            assert_dogstats_increment 1, "security_overview_analytics.tenant_fanout.stopped", tags: ["reason:features_already_initialized"]
            refute_dogstats_increment "security_overview_analytics.tenant_fanout.processed"
          end

          test "enqueues repository owner fanout" do
            RepositoryOwnerJob.expects(:perform_later).with do |**kwargs|
              kwargs[:tenant_scope] == Types::TenantScope::Organization.serialize
              kwargs[:tenant_id] == @org.id
              kwargs[:action] == Types::Action::Initialize.serialize
            end.once
            RepositoryOwnerJob.expects(:perform_later).with do |**kwargs|
              kwargs[:tenant_scope] == Types::TenantScope::Organization.serialize
              kwargs[:tenant_id] == @another_org.id
              kwargs[:action] == Types::Action::Initialize.serialize
            end.once

            BusinessJob.stub_const(:BATCH_SIZE, 1) do
              perform_enqueued_jobs only: [BusinessJob] do
                BusinessJob.perform_now(
                  tenant_scope: Types::TenantScope::Business.serialize,
                  tenant_id: @biz.id,
                  owner_type: Types::Owner::Organization.serialize,
                  action: Types::Action::Initialize.serialize
                )
              end
            end

            Types::Feature.values.each do |feature|
              assert Session.new(
                action: Types::Action::Initialize,
                tenant_scope: Types::TenantScope::Business,
                tenant_id: @biz.id,
                feature:,
                feature_prerequisite: Types::Owner::Organization
              ).locked?
            end

            assert_dogstats_distribution 1, "batched_job.total_time.dist"
            assert_dogstats_increment 3, "security_overview_analytics.tenant_fanout.processed"
            refute_dogstats_increment "security_overview_analytics.tenant_fanout.stopped"
          end
        end

        context "#perform with Action::Reconcile" do
          test "does not perform if provided features not initialized" do
            BusinessJob.any_instance.expects(:perform).never

            BusinessJob.perform_now(
              tenant_scope: Types::TenantScope::Business.serialize,
              tenant_id: @biz.id,
              owner_type: Types::Owner::Organization.serialize,
              action: Types::Action::Reconcile.serialize
            )

            assert_dogstats_increment 1, "security_overview_analytics.tenant_fanout.stopped", tags: ["reason:features_not_initialized"]
            refute_dogstats_increment "security_overview_analytics.tenant_fanout.processed"
          end

          test "does not perform if provided features recently reconciled" do
            Types::Feature.values.each do |feature|
              Session.new(
                action: Types::Action::Initialize,
                tenant_scope: Types::TenantScope::Business,
                tenant_id: @biz.id,
                feature:,
                feature_prerequisite: Types::Owner::Organization
              ).lock!
            end
            Types::Feature.values.each do |feature|
              Session.new(
                action: Types::Action::Reconcile,
                tenant_scope: Types::TenantScope::Business,
                tenant_id: @biz.id,
                feature:,
                feature_prerequisite: Types::Owner::Organization
              ).lock!
            end

            BusinessJob.any_instance.expects(:perform).never

            BusinessJob.perform_now(
              tenant_scope: Types::TenantScope::Business.serialize,
              tenant_id: @biz.id,
              owner_type: Types::Owner::Organization.serialize,
              action: Types::Action::Reconcile.serialize
            )

            assert_dogstats_increment 1, "security_overview_analytics.tenant_fanout.stopped", tags: ["reason:features_reconciled_recently"]
            refute_dogstats_increment "security_overview_analytics.tenant_fanout.processed"
          end
        end

        context "input validations" do
          test "tenant_scope is required" do
            assert_no_enqueued_jobs(only: BusinessJob) do
              assert_raises_with_message(ArgumentError, "Invalid tenant_scope input.") do
                BusinessJob.perform_later(
                  tenant_id: @biz.id,
                  owner_type: Types::Owner::Organization.serialize,
                  action: Types::Action::Initialize.serialize
                )
              end
            end
            refute BusinessJob.new.locked?
          end

          test "only business scope in allowed" do
            assert_no_enqueued_jobs(only: BusinessJob) do
              assert_raises_with_message(ArgumentError, "Invalid tenant_scope input.") do
                BusinessJob.perform_later(
                  tenant_scope: Types::TenantScope::Organization.serialize,
                  tenant_id: @biz.id,
                  owner_type: Types::Owner::Organization.serialize,
                  action: Types::Action::Initialize.serialize
                )
              end
            end

            assert_no_enqueued_jobs(only: BusinessJob) do
              assert_raises_with_message(ArgumentError, "Invalid tenant_scope input.") do
                BusinessJob.perform_later(
                  tenant_scope: Types::TenantScope::User.serialize,
                  tenant_id: @biz.id,
                  owner_type: Types::Owner::Organization.serialize,
                  action: Types::Action::Initialize.serialize
                )
              end
            end

            refute BusinessJob.new.locked?
          end

          test "tenant_scope should match enum value" do
            assert_no_enqueued_jobs(only: BusinessJob) do
              assert_raises_with_message(ArgumentError, "Invalid tenant_scope input.") do
                BusinessJob.perform_later(
                  tenant_scope: "randomscope",
                  tenant_id: @biz.id,
                  owner_type: Types::Owner::Organization.serialize,
                  action: Types::Action::Initialize.serialize
                )
              end
            end
            refute BusinessJob.new.locked?
          end

          test "tenant_id is required" do
            assert_no_enqueued_jobs(only: BusinessJob) do
              assert_raises_with_message(ArgumentError, "Invalid tenant_id input.") do
                BusinessJob.perform_later(
                  tenant_scope: Types::TenantScope::Business.serialize,
                  owner_type: Types::Owner::Organization.serialize,
                  action: Types::Action::Initialize.serialize
                )
              end
            end
            refute BusinessJob.new.locked?
          end

          test "owner_type is required" do
            assert_no_enqueued_jobs(only: BusinessJob) do
              assert_raises_with_message(ArgumentError, "Invalid owner_type input.") do
                BusinessJob.perform_later(
                  tenant_scope: Types::TenantScope::Business.serialize,
                  tenant_id: @biz.id,
                  action: Types::Action::Initialize.serialize
                )
              end
            end
            refute BusinessJob.new.locked?
          end

          test "owner_type input should match enum value" do
            assert_no_enqueued_jobs(only: BusinessJob) do
              assert_raises_with_message(ArgumentError, "Invalid owner_type input.") do
                BusinessJob.perform_later(
                  tenant_scope: Types::TenantScope::Business.serialize,
                  tenant_id: @biz.id,
                  owner_type: "randomowner",
                  action: Types::Action::Initialize.serialize
                )
              end
            end
            refute BusinessJob.new.locked?
          end

          test "action is required" do
            assert_no_enqueued_jobs(only: BusinessJob) do
              assert_raises_with_message(ArgumentError, "Invalid action input.") do
                BusinessJob.perform_later(
                  tenant_scope: Types::TenantScope::Business.serialize,
                  tenant_id: @biz.id,
                  owner_type: Types::Owner::Organization.serialize
                )
              end
            end
            refute BusinessJob.new.locked?
          end

          test "action input should match enum value" do
            assert_no_enqueued_jobs(only: BusinessJob) do
              assert_raises_with_message(ArgumentError, "Invalid action input.") do
                BusinessJob.perform_later(
                  tenant_scope: Types::TenantScope::Business.serialize,
                  tenant_id: @biz.id,
                  owner_type: Types::Owner::Organization.serialize,
                  action: "randomaction"
                )
              end
            end
            refute BusinessJob.new.locked?
          end

          test "features input should match enum value" do
            assert_no_enqueued_jobs(only: BusinessJob) do
              assert_raises_with_message(ArgumentError, "Invalid features input.") do
                BusinessJob.perform_later(
                  tenant_scope: Types::TenantScope::Business.serialize,
                  tenant_id: @biz.id,
                  owner_type: Types::Owner::Organization.serialize,
                  action: Types::Action::Initialize.serialize,
                  features: ["randomfeature"]
                )
              end
            end
            refute BusinessJob.new.locked?
          end

          test "stops if tenant not found" do
            BusinessJob.any_instance.expects(:perform).never

            BusinessJob.perform_now(
              tenant_scope: Types::TenantScope::Business.serialize,
              tenant_id: 9999999999,
              owner_type: Types::Owner::Organization.serialize,
              action: Types::Action::Initialize.serialize
            )

            assert_dogstats_increment 1, "security_overview_analytics.tenant_fanout.stopped", tags: ["reason:tenant_not_found"]
            refute_dogstats_increment "security_overview_analytics.tenant_fanout.processed"
          end
        end

        context "on multi tenant enterprise" do
          test "sets the tenant context to the correct business" do
            on_multi_tenant_enterprise do
              ::Business.expects(:find_by).with(id: @mt_biz.id).returns(@mt_biz).twice
              BusinessJob.perform_now(
                tenant_scope: Types::TenantScope::Business.serialize,
                tenant_id: @mt_biz.id,
                owner_type: Types::Owner::Organization.serialize,
                action: Types::Action::Initialize.serialize
              )
            end
          end
        end
      end

      context "user owner type" do
        context "#perform with Action::Initialize" do
          test "does not perform if provided features already initialized" do
            Types::Feature.values.each do |feature|
              Session.new(
                action: Types::Action::Initialize,
                tenant_scope: Types::TenantScope::Business,
                tenant_id: @biz.id,
                feature:,
                feature_prerequisite: Types::Owner::User
              ).lock!
            end

            BusinessJob.any_instance.expects(:perform).never

            BusinessJob.perform_now(
              tenant_scope: Types::TenantScope::Business.serialize,
              tenant_id: @biz.id,
              owner_type: Types::Owner::User.serialize,
              action: Types::Action::Initialize.serialize
            )

            assert_dogstats_increment 1, "security_overview_analytics.tenant_fanout.stopped", tags: ["reason:features_already_initialized"]
            refute_dogstats_increment "security_overview_analytics.tenant_fanout.processed"
          end

          test "does not enqueues repository owner fanout for pull request alerts" do
            RepositoryOwnerJob.expects(:perform_later).never

            perform_enqueued_jobs only: [BusinessJob] do
              BusinessJob.perform_now(
                tenant_scope: Types::TenantScope::Business.serialize,
                tenant_id: @biz.id,
                owner_type: Types::Owner::User.serialize,
                action: Types::Action::Initialize.serialize
              )
            end
          end
        end

        context "#perform with Action::Reconcile" do
          test "does not perform if provided features not initialized" do
            BusinessJob.any_instance.expects(:perform).never

            BusinessJob.perform_now(
              tenant_scope: Types::TenantScope::Business.serialize,
              tenant_id: @biz.id,
              owner_type: Types::Owner::User.serialize,
              action: Types::Action::Reconcile.serialize
            )

            assert_dogstats_increment 1, "security_overview_analytics.tenant_fanout.stopped", tags: ["reason:features_not_initialized"]
            refute_dogstats_increment "security_overview_analytics.tenant_fanout.processed"
          end
        end

        context "input validations" do
          test "tenant_scope is required" do
            assert_no_enqueued_jobs(only: BusinessJob) do
              assert_raises_with_message(ArgumentError, "Invalid tenant_scope input.") do
                BusinessJob.perform_later(
                  tenant_id: @biz.id,
                  owner_type: Types::Owner::User.serialize,
                  action: Types::Action::Initialize.serialize
                )
              end
            end
            refute BusinessJob.new.locked?
          end

          test "only business scope in allowed" do
            assert_no_enqueued_jobs(only: BusinessJob) do
              assert_raises_with_message(ArgumentError, "Invalid tenant_scope input.") do
                BusinessJob.perform_later(
                  tenant_scope: Types::TenantScope::Organization.serialize,
                  tenant_id: @biz.id,
                  owner_type: Types::Owner::User.serialize,
                  action: Types::Action::Initialize.serialize
                )
              end
            end

            assert_no_enqueued_jobs(only: BusinessJob) do
              assert_raises_with_message(ArgumentError, "Invalid tenant_scope input.") do
                BusinessJob.perform_later(
                  tenant_scope: Types::TenantScope::User.serialize,
                  tenant_id: @biz.id,
                  owner_type: Types::Owner::User.serialize,
                  action: Types::Action::Initialize.serialize
                )
              end
            end

            refute BusinessJob.new.locked?
          end

          test "tenant_scope should match enum value" do
            assert_no_enqueued_jobs(only: BusinessJob) do
              assert_raises_with_message(ArgumentError, "Invalid tenant_scope input.") do
                BusinessJob.perform_later(
                  tenant_scope: "randomscope",
                  tenant_id: @biz.id,
                  owner_type: Types::Owner::User.serialize,
                  action: Types::Action::Initialize.serialize
                )
              end
            end
            refute BusinessJob.new.locked?
          end

          test "tenant_id is required" do
            assert_no_enqueued_jobs(only: BusinessJob) do
              assert_raises_with_message(ArgumentError, "Invalid tenant_id input.") do
                BusinessJob.perform_later(
                  tenant_scope: Types::TenantScope::Business.serialize,
                  owner_type: Types::Owner::User.serialize,
                  action: Types::Action::Initialize.serialize
                )
              end
            end
            refute BusinessJob.new.locked?
          end

          test "owner_type is required" do
            assert_no_enqueued_jobs(only: BusinessJob) do
              assert_raises_with_message(ArgumentError, "Invalid owner_type input.") do
                BusinessJob.perform_later(
                  tenant_scope: Types::TenantScope::Business.serialize,
                  tenant_id: @biz.id,
                  action: Types::Action::Initialize.serialize
                )
              end
            end
            refute BusinessJob.new.locked?
          end

          test "owner_type input should match enum value" do
            assert_no_enqueued_jobs(only: BusinessJob) do
              assert_raises_with_message(ArgumentError, "Invalid owner_type input.") do
                BusinessJob.perform_later(
                  tenant_scope: Types::TenantScope::Business.serialize,
                  tenant_id: @biz.id,
                  owner_type: "randomowner",
                  action: Types::Action::Initialize.serialize
                )
              end
            end
            refute BusinessJob.new.locked?
          end

          test "action is required" do
            assert_no_enqueued_jobs(only: BusinessJob) do
              assert_raises_with_message(ArgumentError, "Invalid action input.") do
                BusinessJob.perform_later(
                  tenant_scope: Types::TenantScope::Business.serialize,
                  tenant_id: @biz.id,
                  owner_type: Types::Owner::User.serialize
                )
              end
            end
            refute BusinessJob.new.locked?
          end

          test "action input should match enum value" do
            assert_no_enqueued_jobs(only: BusinessJob) do
              assert_raises_with_message(ArgumentError, "Invalid action input.") do
                BusinessJob.perform_later(
                  tenant_scope: Types::TenantScope::Business.serialize,
                  tenant_id: @biz.id,
                  owner_type: Types::Owner::User.serialize,
                  action: "randomaction"
                )
              end
            end
            refute BusinessJob.new.locked?
          end

          test "features input should match enum value" do
            assert_no_enqueued_jobs(only: BusinessJob) do
              assert_raises_with_message(ArgumentError, "Invalid features input.") do
                BusinessJob.perform_later(
                  tenant_scope: Types::TenantScope::Business.serialize,
                  tenant_id: @biz.id,
                  owner_type: Types::Owner::User.serialize,
                  action: Types::Action::Initialize.serialize,
                  features: ["randomfeature"]
                )
              end
            end
            refute BusinessJob.new.locked?
          end

          test "stops if tenant not found" do
            BusinessJob.any_instance.expects(:perform).never

            BusinessJob.perform_now(
              tenant_scope: Types::TenantScope::Business.serialize,
              tenant_id: 9999999999,
              owner_type: Types::Owner::User.serialize,
              action: Types::Action::Initialize.serialize
            )

            assert_dogstats_increment 1, "security_overview_analytics.tenant_fanout.stopped", tags: ["reason:tenant_not_found"]
            refute_dogstats_increment "security_overview_analytics.tenant_fanout.processed"
          end

          test "stops if business is not enterprise managed", skip_enterprise: true do
            BusinessJob.any_instance.expects(:perform).never
            Business.any_instance.stubs(:enterprise_managed?).returns(false)

            BusinessJob.perform_now(
              tenant_scope: Types::TenantScope::Business.serialize,
              tenant_id: @biz.id,
              owner_type: Types::Owner::User.serialize,
              action: Types::Action::Initialize.serialize
            )

            assert_dogstats_increment 1, "security_overview_analytics.tenant_fanout.stopped", tags: ["reason:user_owner_not_supported"]
            refute_dogstats_increment "security_overview_analytics.tenant_fanout.processed"
          end
        end

        context "on multi tenant enterprise" do
          test "sets the tenant context to the correct business" do
            on_multi_tenant_enterprise do
              ::Business.expects(:find_by).with(id: @mt_biz.id).returns(@mt_biz).twice
              BusinessJob.perform_now(
                tenant_scope: Types::TenantScope::Business.serialize,
                tenant_id: @mt_biz.id,
                owner_type: Types::Owner::User.serialize,
                action: Types::Action::Initialize.serialize
              )
            end
          end
        end
      end

      context "resiliency" do
        test "it retries on standard conditions" do
          assert_retry_conditions(
            job: BusinessJob,
            args: [
              tenant_scope: Types::TenantScope::Business.serialize,
              tenant_id: @biz.id,
              owner_type: Types::Owner::Organization.serialize,
              action: Types::Action::Initialize.serialize
            ],
            using_kwargs: true
          )
        end
      end

      context "hash lock" do
        test "does not allow concurrent jobs for the same pull request" do
          assert_enqueued_jobs 1, only: BusinessJob do
            BusinessJob.perform_later(
              tenant_scope: Types::TenantScope::Business.serialize,
              tenant_id: @biz.id,
              owner_type: Types::Owner::Organization.serialize,
              action: Types::Action::Initialize.serialize
            )
            BusinessJob.perform_later(
              tenant_scope: Types::TenantScope::Business.serialize,
              tenant_id: @biz.id,
              owner_type: Types::Owner::Organization.serialize,
              action: Types::Action::Initialize.serialize,
              features: ["test"]
            )
            BusinessJob.perform_later(
              tenant_scope: Types::TenantScope::Business.serialize,
              tenant_id: @biz.id,
              owner_type: Types::Owner::Organization.serialize,
              action: Types::Action::Initialize.serialize,
              features: [Types::Feature::CodeScanningPullRequestAlert.serialize]
            )
          end
        end
      end
    end
  end
end
