# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class CodeScanningAutoCodeqlFeatureToggledJobTest < GitHub::TestCase
    include GitHub::QueryAssertionTestHelpers
    include DogstatsTestHelpers
    include JobTestHelper

    fixtures do
      @user = create(:user)
      @org = create(:organization, admin: @user)
      @repo = create(:repository, owner: @org)

      on_multi_tenant_enterprise do
        @mt_user = create(:emu)
        @mt_business = @mt_user.enterprise_managed_business
        @mt_org = create :enterprise_linked_organization, :with_org_namespacing, business: @mt_business, admin: @mt_user
        @mt_repo = create(:private_repository, owner: @mt_org, admin: @mt_user, from_example: :simple)
      end
    end

    setup do
      @utc_now = Time.current.utc
      @date_id = ::SecurityOverviewAnalytics::Date.id_from_time(@utc_now)

      TenantValidationHelper.stubs(:should_handle_feature_enablement_events?).returns(true)

      ::Repository.any_instance.stubs(:code_scanning_auto_codeql_security_center_status)
        .returns(::Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 0))
    end

    context "#perform" do
      test "can create data on feature toggle event" do
        refute FeatureStatusRevision.find_by(repository_id: @repo.id, date_id: @date_id)

        assert_query_counts(11) do
          CodeScanningAutoCodeqlFeatureToggledJob.perform_now(
            repository_id: @repo.id,
            source_event: "repo.codeql_enabled",
          )
        end

        new_record = FeatureStatusRevision.find_by(repository_id: @repo.id, date_id: @date_id)
        assert new_record
        assert_equal SecurityOverviewAnalytics::Date::FUTURE_DATE_ID, new_record&.next_revision_date_id
        assert new_record&.code_scanning_auto_codeql_enabled
        assert new_record&.code_scanning_auto_codeql_eligible

        refute_dogstats_increment "security_overview_analytics.event.code_scanning_auto_codeql_feature_toggled.skipped"
      end

      test "does nothing if repository owner validation fails" do
        TenantValidationHelper.stubs(:should_handle_feature_enablement_events?).returns(false)

        assert_query_counts(2) do
          CodeScanningAutoCodeqlFeatureToggledJob.perform_now(
            repository_id: @repo.id,
            source_event: "repo.codeql_enabled",
          )
        end

        refute FeatureStatusRevision.find_by(repository_id: @repo.id, date_id: @date_id)
        assert_dogstats_increment 1, "security_overview_analytics.event.code_scanning_auto_codeql_feature_toggled.skipped", tags: ["reason:ineligible_owner"]
      end

      test "can create revision on new date" do
        last_revision = create(
          :soa_feature_status_revision,
          date_id: @date_id - 1,
          next_revision_date_id: SecurityOverviewAnalytics::Date::FUTURE_DATE_ID,
          code_scanning_auto_codeql_enabled: false,
          code_scanning_auto_codeql_eligible: false,
        )
        refute last_revision.code_scanning_auto_codeql_enabled
        refute last_revision.code_scanning_auto_codeql_eligible

        Timecop.freeze(@utc_now) do
          assert_query_counts(16) do
            CodeScanningAutoCodeqlFeatureToggledJob.perform_now(
              repository_id: last_revision.repository_id,
              source_event: "repo.codeql_enabled",
            )
          end
        end

        last_revision.reload
        refute last_revision.code_scanning_auto_codeql_enabled
        refute last_revision.code_scanning_auto_codeql_eligible
        assert_equal @date_id - 1, last_revision.date_id
        assert_equal @date_id, last_revision.next_revision_date_id

        new_revision = FeatureStatusRevision.find_by(
          next_revision_date_id: Date::FUTURE_DATE_ID,
          repository_id: last_revision.repository_id
        )
        assert_equal @date_id, new_revision&.date_id
        assert new_revision&.code_scanning_auto_codeql_enabled
        assert new_revision&.code_scanning_auto_codeql_eligible

        refute_dogstats_increment "security_overview_analytics.event.code_scanning_auto_codeql_feature_toggled.skipped"
      end

      test "can update revision on the same date" do
        last_revision = create(
          :soa_feature_status_revision,
          date_id: @date_id,
          next_revision_date_id: SecurityOverviewAnalytics::Date::FUTURE_DATE_ID,
          code_scanning_auto_codeql_enabled: false,
          code_scanning_auto_codeql_eligible: false,
        )
        refute last_revision.code_scanning_auto_codeql_enabled
        refute last_revision.code_scanning_auto_codeql_eligible

        Timecop.freeze(@utc_now) do
          assert_query_counts(12) do
            CodeScanningAutoCodeqlFeatureToggledJob.perform_now(
              repository_id: last_revision.repository_id,
              source_event: "repo.codeql_enabled",
            )
          end
        end

        last_revision.reload
        assert last_revision.code_scanning_auto_codeql_enabled
        assert last_revision.code_scanning_auto_codeql_eligible
        assert_equal @date_id, last_revision.date_id
        assert_equal SecurityOverviewAnalytics::Date::FUTURE_DATE_ID, last_revision.next_revision_date_id

        refute_dogstats_increment "security_overview_analytics.event.code_scanning_auto_codeql_feature_toggled.skipped"
      end

      test "can update with enabled status" do
        ::Repository.any_instance.stubs(:code_scanning_auto_codeql_security_center_status)
          .returns(::Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("enrolled", 0))

        refute FeatureStatusRevision.find_by(repository_id: @repo.id, date_id: @date_id)

        assert_query_counts(11) do
          CodeScanningAutoCodeqlFeatureToggledJob.perform_now(
            repository_id: @repo.id,
            source_event: "repo.codeql_enabled",
          )
        end

        new_record = FeatureStatusRevision.find_by(repository_id: @repo.id, date_id: @date_id)
        assert new_record
        assert_equal SecurityOverviewAnalytics::Date::FUTURE_DATE_ID, new_record&.next_revision_date_id
        assert new_record&.code_scanning_auto_codeql_enabled
        assert new_record&.code_scanning_auto_codeql_eligible
      end

      test "can update with eligible status" do
        ::Repository.any_instance.stubs(:code_scanning_auto_codeql_security_center_status)
          .returns(::Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("eligible", 0))

        refute FeatureStatusRevision.find_by(repository_id: @repo.id, date_id: @date_id)

        assert_query_counts(11) do
          CodeScanningAutoCodeqlFeatureToggledJob.perform_now(
            repository_id: @repo.id,
            source_event: "repo.codeql_enabled",
          )
        end

        new_record = FeatureStatusRevision.find_by(repository_id: @repo.id, date_id: @date_id)
        assert new_record
        assert_equal SecurityOverviewAnalytics::Date::FUTURE_DATE_ID, new_record&.next_revision_date_id
        refute new_record&.code_scanning_auto_codeql_enabled
        assert new_record&.code_scanning_auto_codeql_eligible
      end

      test "can update with disabled status" do
        ::Repository.any_instance.stubs(:code_scanning_auto_codeql_security_center_status)
          .returns(::Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("not_eligible", 0))

        refute FeatureStatusRevision.find_by(repository_id: @repo.id, date_id: @date_id)

        assert_query_counts(11) do
          CodeScanningAutoCodeqlFeatureToggledJob.perform_now(
            repository_id: @repo.id,
            source_event: "repo.codeql_enabled",
          )
        end

        new_record = FeatureStatusRevision.find_by(repository_id: @repo.id, date_id: @date_id)
        assert new_record
        assert_equal SecurityOverviewAnalytics::Date::FUTURE_DATE_ID, new_record&.next_revision_date_id
        refute new_record&.code_scanning_auto_codeql_enabled
        refute new_record&.code_scanning_auto_codeql_eligible
      end
    end

    context "resiliency" do
      test "it retries on standard conditions" do
        assert_retry_conditions(
          job: CodeScanningAutoCodeqlFeatureToggledJob,
          args: [repository_id: @repo.id, source_event: "foo"],
          using_kwargs: true
        )
      end

      test "retries on transient errors" do
        CodeScanningAutoCodeqlFeatureToggledJob::RETRYABLE_EXCEPTIONS.each do |error|
          assert_retry_on_error(
            error,
            CodeScanningAutoCodeqlFeatureToggledJob,
            [{ repository_id: @repo.id, source_event: "foobar" }],
            true,
          )
        end
      end
    end

    context "hash lock" do
      test "does not allow concurrent jobs for the same repository" do
        assert_enqueued_jobs 1, only: CodeScanningAutoCodeqlFeatureToggledJob do
          CodeScanningAutoCodeqlFeatureToggledJob.perform_later(repository_id: @repo.id, source_event: "foo")
          CodeScanningAutoCodeqlFeatureToggledJob.perform_later(repository_id: @repo.id, source_event: "bar")
        end
      end
    end

    context "on multi tenant enterprise" do
      test "sets the tenant context to the correct business" do
        on_multi_tenant_enterprise do
          ::Repositories::Public.expects(:resolve_tenant).with(id: @mt_repo.id).returns(@mt_business).once
          CodeScanningAutoCodeqlFeatureToggledJob.perform_now(repository_id: @mt_repo.id, source_event: "foo")
        end
      end
    end

    context "pubsub" do
      test "enqueues job when AutoCodeQL is enabled" do
        GitHub::Turboscan::ManagedAnalyses.expects(:enable)
          .returns(Twirp::ClientResp.new(data: ::Turboscan::Proto::EnableResponse.new))

        clear_enqueued_jobs
        assert_enqueued_with(job: CodeScanningAutoCodeqlFeatureToggledJob, args: [{ repository_id: @repo.id, source_event: "repo.codeql_enabled" }]) do
          CodeScanning::AutoCodeql.new(@repo).enable(actor: @user, options: { action: :enable })
        end
      end

      test "enqueues job when AutoCodeQL is updated" do
        GitHub::Turboscan::ManagedAnalyses.expects(:update)
          .returns(Twirp::ClientResp.new(data: ::Turboscan::Proto::EnableResponse.new))

        clear_enqueued_jobs
        assert_enqueued_with(job: CodeScanningAutoCodeqlFeatureToggledJob, args: [{ repository_id: @repo.id, source_event: "repo.codeql_updated" }]) do
          CodeScanning::AutoCodeql.new(@repo).enable(actor: @user, options: { action: :update })
        end
      end

      test "enqueues job when AutoCodeQL is disabled" do
        GitHub::Turboscan::ManagedAnalyses.expects(:disable)
          .returns(Twirp::ClientResp.new(data: ::Turboscan::Proto::EnableResponse.new))

        clear_enqueued_jobs
        assert_enqueued_with(job: CodeScanningAutoCodeqlFeatureToggledJob, args: [{ repository_id: @repo.id, source_event: "repo.codeql_disabled" }]) do
          CodeScanning::AutoCodeql.new(@repo).disable(actor: @user, options: {})
        end
      end
    end
  end
end
