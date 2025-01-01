# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class Backfill::CodeScanningAlertNumberJobTest < GitHub::TestCase
    include DogstatsTestHelpers

    fixtures do
      @base_date = ::Date.new(2024, 6, 1).freeze
      base_date_id = ::SecurityOverviewAnalytics::Date.id_from_date(@base_date)

      @biz = create(:business)
      @org = create(:organization, business: @biz, admin: @org_admin)
      @alert_numbers = (1..6)
      @alert_id_mod = 1000

      @repo_not_backfilled = create(:private_repository, owner: @org).tap do |r|
        @alert_numbers.each do |number|
          alert_id = @alert_id_mod + number
          alert_number = alert_id
          date_id = base_date_id + (number % 3)
          create(:soa_code_scanning_alert_revision, repository: r, alert_number:, alert_id:, date_id:)
        end
      end

      @repo_half_backfilled = create(:private_repository, owner: @org).tap do |r|
        mid_index = @alert_numbers.count / 2

        @alert_numbers.to_a[...mid_index]&.each do |number|
          alert_id = @alert_id_mod + number
          alert_number = number
          date_id = base_date_id + (number % 3)
          create(:soa_code_scanning_alert_revision, repository: r, alert_number:, alert_id:, date_id:)
        end

        @alert_numbers.to_a[mid_index..]&.each do |number|
          alert_id = @alert_id_mod + number
          alert_number = alert_id
          date_id = base_date_id + (number % 3)
          create(:soa_code_scanning_alert_revision, repository: r, alert_number:, alert_id:, date_id:)
        end
      end

      @repo_backfilled = create(:private_repository, owner: @org).tap do |r|
        @alert_numbers.each do |number|
          alert_id = @alert_id_mod + number
          alert_number = number
          date_id = base_date_id + (number % 3)
          create(:soa_code_scanning_alert_revision, repository: r, alert_number:, alert_id:, date_id:)
        end
      end

      @repo_backfilled_with_duplicated_revisions = create(:private_repository, owner: @org).tap do |r|
        mid_index = @alert_numbers.count / 2

        @alert_numbers.each do |number|
          alert_id = @alert_id_mod + number
          alert_number = number
          date_id = base_date_id + (number % 3)
          create(:soa_code_scanning_alert_revision, repository: r, alert_number:, alert_id:, date_id:).tap do |rev|
            next unless number > mid_index
            # Also creates duplicated records
            dup_rev = rev.dup
            dup_rev.alert_number = alert_id
            # bumps timestamp for duplicated revisions to validate if upsert happened
            dup_rev.alert_updated_at = rev.alert_updated_at + 1.hour
            dup_rev.save!
          end
        end
      end

      @repo_with_duplicated_and_not_backfilled_revisions = create(:private_repository, owner: @org).tap do |r|
        mid_index = @alert_numbers.count / 2

        @alert_numbers.each do |number|
          alert_id = @alert_id_mod + number
          date_id = base_date_id + (number % 3)

          if number > mid_index
            # half are backfilled with dup revisions
            alert_number = number
            create(:soa_code_scanning_alert_revision, repository: r, alert_number:, alert_id:, date_id:).tap do |rev|
              # creates duplicated records
              dup_rev = rev.dup
              dup_rev.alert_number = alert_id
              # bumps timestamp for duplicated revisions to validate if upsert happened
              dup_rev.alert_updated_at = rev.alert_updated_at + 1.hour
              dup_rev.save!
            end
          else
            # half are not backfilled
            alert_number = alert_id
            create(:soa_code_scanning_alert_revision, repository: r, alert_number:, alert_id:, date_id:)
          end
        end
      end

      @repo_partly_backfilled_alerts = create(:private_repository, owner: @org).tap do |r|
        mid_index = @alert_numbers.count / 2

        @alert_numbers.each do |number|
          alert_id = @alert_id_mod + number
          alert_number = number
          date_id = base_date_id + (number % 3)
          create(:soa_code_scanning_alert_revision, repository: r, alert_number:, alert_id:, date_id: date_id - 1, next_revision_date_id: date_id).tap do |rev|
            pending_alert_number = number > mid_index ? alert_id : alert_number
            create(:soa_code_scanning_alert_revision, repository: r, alert_number: pending_alert_number, alert_id:, date_id:, alert_updated_at: rev.alert_updated_at + 1.hour)
          end
        end
      end
    end

    setup do
      GitHub.flipper[:security_center_backfill_code_scanning_alert_number].enable
      GitHub.flipper[:security_center_backfill_code_scanning_alert_number_dry_run].disable
      GitHub.flipper[:soa_backfill_code_scanning_alert_number_job_restraint_lock_num_concurrent_jobs].enable_percentage_of_actors(10.0)
      GitHub.flipper[:soa_backfill_code_scanning_alert_number_job_restraint_lock_ttl_minutes].enable_percentage_of_actors(60.0)
    end

    context "on multi tenant enterprise" do
      test "sets the tenant context to the correct business" do
        on_multi_tenant_enterprise do
          mt_user = create(:emu)
          mt_business = mt_user.enterprise_managed_business
          GitHub::CurrentTenant.set(mt_business)
          mt_org = create :enterprise_linked_organization, :with_org_namespacing, business: mt_business, admin: mt_user
          mt_repo = create(:private_repository, owner: mt_org)

          # Simulate no tenant being set
          GitHub::CurrentTenant.remove
          assert_nil GitHub::CurrentTenant.get
          refute_predicate GitHub::CurrentTenant, :unscoped?

          Repositories::Public.expects(:resolve_tenant).at_least_once.with(id: mt_repo.id).returns(mt_business)
          Backfill::CodeScanningAlertNumberJob.perform_now(repository_id: mt_repo.id)
        end
      end
    end

    test "it updates alert_number with actual alert ids" do
      numbers_before = CodeScanningAlertRevision
        .where(repository_id: @repo_not_backfilled.id)
        .order(:id)
        .pluck(:alert_number)
      numbers_after = numbers_before.map do |n|
        n - @alert_id_mod
      end

      setup_ts_request(@repo_not_backfilled)

      assert_changes(
        -> do
          CodeScanningAlertRevision
            .where(repository_id: @repo_not_backfilled.id)
            .order(:id)
            .pluck(:alert_number)
        end,
        from: numbers_before,
        to: numbers_after
      ) do
        Backfill::CodeScanningAlertNumberJob.perform_now(repository_id: @repo_not_backfilled.id)
      end
    end

    test "it completes the backfill if repository is half backfilled" do
      numbers_before = CodeScanningAlertRevision
        .where(repository_id: @repo_half_backfilled.id)
        .order(:id)
        .pluck(:alert_number)
      numbers_after = numbers_before.map do |n|
        next n if n < @alert_id_mod
        n - @alert_id_mod
      end

      setup_ts_request(@repo_half_backfilled)

      assert_changes(
        -> do
          CodeScanningAlertRevision
            .where(repository_id: @repo_half_backfilled.id)
            .order(:id)
            .pluck(:alert_number)
        end,
        from: numbers_before,
        to: numbers_after
      ) do
        Backfill::CodeScanningAlertNumberJob.perform_now(repository_id: @repo_half_backfilled.id)
      end
    end

    test "it does not update rows if all are backfilled" do
      setup_ts_request(@repo_backfilled)

      CodeScanningAlertRevision.expects(:throttle_writes_with_retry).never
      Backfill::CodeScanningAlertNumberJob.perform_now(repository_id: @repo_backfilled.id)
    end

    test "it only processes the same alert id once" do
      num_of_revs = CodeScanningAlertRevision
        .where(repository_id: @repo_not_backfilled.id)
        .size

      setup_ts_request(@repo_not_backfilled, include_initial_revs: true)

      CodeScanningAlertRevision.expects(:throttle_writes_with_retry).at_most(num_of_revs)
      Backfill::CodeScanningAlertNumberJob.perform_now(repository_id: @repo_not_backfilled.id)
    end

    context "when repo contains duplicated revisions" do
      test "it replays duplicated revisions and cleans up duplicated entries" do
        GitHub.flipper[:security_center_backfill_code_scanning_alert_number_process_duplicated_revisions].enable

        numbers_before = CodeScanningAlertRevision
          .where(repository_id: @repo_backfilled_with_duplicated_revisions.id)
          .order(:id)
          .pluck(:alert_number, :alert_updated_at)
        numbers_after = numbers_before.reduce([]) do |out, (alert_number, alert_updated_at)|
          next out if alert_number > @alert_id_mod
          alert_updated_at += 1.hour if alert_number > @alert_numbers.count / 2
          out << [alert_number, alert_updated_at]
        end

        setup_ts_request(@repo_backfilled_with_duplicated_revisions)

        assert_changes(
          -> do
            CodeScanningAlertRevision
              .where(repository_id: @repo_backfilled_with_duplicated_revisions.id)
              .order(:id)
              .pluck(:alert_number, :alert_updated_at)
          end,
          from: numbers_before,
          to: numbers_after
        ) do
          Backfill::CodeScanningAlertNumberJob.perform_now(repository_id: @repo_backfilled_with_duplicated_revisions.id)
        end
      end

      test "it backfills remaining revisions if they are not backfilled yet" do
        GitHub.flipper[:security_center_backfill_code_scanning_alert_number_process_duplicated_revisions].enable

        numbers_before = CodeScanningAlertRevision
          .where(repository_id: @repo_with_duplicated_and_not_backfilled_revisions.id)
          .order(:id)
          .pluck(:alert_number, :alert_updated_at)
        numbers_after = numbers_before.reduce([]) do |out, (alert_number, alert_updated_at)|
          if alert_number > @alert_id_mod
            # Ignore dup revisions
            next out if alert_number > (@alert_id_mod + @alert_numbers.count / 2)
            out << [alert_number - @alert_id_mod, alert_updated_at]
          else
            out << [alert_number, alert_updated_at + 1.hour]
          end
        end

        setup_ts_request(@repo_with_duplicated_and_not_backfilled_revisions)

        assert_changes(
          -> do
            CodeScanningAlertRevision
              .where(repository_id: @repo_with_duplicated_and_not_backfilled_revisions.id)
              .order(:id)
              .pluck(:alert_number, :alert_updated_at)
          end,
          from: numbers_before,
          to: numbers_after
        ) do
          Backfill::CodeScanningAlertNumberJob.perform_now(repository_id: @repo_with_duplicated_and_not_backfilled_revisions.id)
        end
      end

      test "it does nothing to duplicated revisions if flag is disabled" do
        GitHub.flipper[:security_center_backfill_code_scanning_alert_number_process_duplicated_revisions].disable

        setup_ts_request(@repo_backfilled_with_duplicated_revisions)

        assert_no_changes(
          -> do
            CodeScanningAlertRevision
              .where(repository_id: @repo_backfilled_with_duplicated_revisions.id)
              .order(:id)
              .pluck(:alert_number, :alert_updated_at)
          end
        ) do
          Backfill::CodeScanningAlertNumberJob.perform_now(repository_id: @repo_backfilled_with_duplicated_revisions.id)
        end
      end

      test "it does nothing to duplicated revisions if dry run mode is ON" do
        GitHub.flipper[:security_center_backfill_code_scanning_alert_number_dry_run].enable
        GitHub.flipper[:security_center_backfill_code_scanning_alert_number_process_duplicated_revisions].enable

        setup_ts_request(@repo_backfilled_with_duplicated_revisions)

        assert_no_changes(
          -> do
            CodeScanningAlertRevision
              .where(repository_id: @repo_backfilled_with_duplicated_revisions.id)
              .order(:id)
              .pluck(:alert_number, :alert_updated_at)
          end
        ) do
          Backfill::CodeScanningAlertNumberJob.perform_now(repository_id: @repo_backfilled_with_duplicated_revisions.id)
        end
      end
    end

    context "replay mode" do
      test "is off if not explicitly specified" do
        setup_ts_request(@repo_partly_backfilled_alerts)
        ::SecurityOverviewAnalytics::CodeScanningAlertRevision.expects(:upsert_revision).never
        Backfill::CodeScanningAlertNumberJob.perform_now(repository_id: @repo_partly_backfilled_alerts.id)
      end

      test "is on if explicitly specified" do
        setup_ts_request(@repo_partly_backfilled_alerts)
        ::SecurityOverviewAnalytics::CodeScanningAlertRevision.expects(:upsert_revision).times(3)
        Backfill::CodeScanningAlertNumberJob.perform_now(repository_id: @repo_partly_backfilled_alerts.id, backfill_mode: :replay)
      end

      context "when it is on" do
        test "it backfills revisions with replay if alert revisions are partially backfilled" do
          numbers_before = CodeScanningAlertRevision
            .where(repository_id: @repo_partly_backfilled_alerts.id)
            .order(:alert_id, :id)
            .pluck(:alert_number, :alert_updated_at)
          numbers_after = numbers_before.reduce([]) do |out, (alert_number, alert_updated_at)|
            n = alert_number > @alert_id_mod ? alert_number - @alert_id_mod : alert_number
            out << [n, alert_updated_at]
          end

          setup_ts_request(@repo_partly_backfilled_alerts)

          assert_changes(
            -> do
              CodeScanningAlertRevision
                .where(repository_id: @repo_partly_backfilled_alerts.id)
                .order(:alert_id, :id)
                .pluck(:alert_number, :alert_updated_at)
            end,
            from: numbers_before,
            to: numbers_after
          ) do
            Backfill::CodeScanningAlertNumberJob.perform_now(repository_id: @repo_partly_backfilled_alerts.id, backfill_mode: :replay)
          end
        end

        test "it does nothing if dry run mode is ON" do
          GitHub.flipper[:security_center_backfill_code_scanning_alert_number_dry_run].enable

          setup_ts_request(@repo_partly_backfilled_alerts)

          assert_no_changes(
            -> do
              CodeScanningAlertRevision
                .where(repository_id: @repo_partly_backfilled_alerts.id)
                .order(:id)
                .pluck(:alert_number, :alert_updated_at)
            end
          ) do
            Backfill::CodeScanningAlertNumberJob.perform_now(repository_id: @repo_partly_backfilled_alerts.id)
          end
        end

        test "it is not used when alert revisions are either all backfilled or all pending" do
          numbers_before = CodeScanningAlertRevision
            .where(repository_id: @repo_half_backfilled.id)
            .order(:id)
            .pluck(:alert_number)
          numbers_after = numbers_before.map do |n|
            next n if n < @alert_id_mod
            n - @alert_id_mod
          end

          setup_ts_request(@repo_half_backfilled)

          ::SecurityOverviewAnalytics::CodeScanningAlertRevision.expects(:upsert_revision).never

          assert_changes(
            -> do
              CodeScanningAlertRevision
                .where(repository_id: @repo_half_backfilled.id)
                .order(:id)
                .pluck(:alert_number)
            end,
            from: numbers_before,
            to: numbers_after
          ) do
            Backfill::CodeScanningAlertNumberJob.perform_now(repository_id: @repo_half_backfilled.id, backfill_mode: :replay)
          end
        end
      end
    end

    context 'when feature flag "security_center_backfill_code_scanning_alert_number" is disabled' do
      test "it does not perform the job" do
        GitHub.flipper[:security_center_backfill_code_scanning_alert_number].disable

        ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill).never

        assert_no_changes(
          -> do
            CodeScanningAlertRevision
              .where(repository_id: @repo_not_backfilled.id)
              .order(:id)
              .pluck(:alert_number)
          end
        ) do
          Backfill::CodeScanningAlertNumberJob.perform_now(repository_id: @repo_not_backfilled.id)
        end

        refute_dogstats_distribution "batched_job.time.dist"
      end
    end

    context "when dry_run mode is on" do
      test "it performs but does not update alert_number column" do
        GitHub.flipper[:security_center_backfill_code_scanning_alert_number_dry_run].enable

        setup_ts_request(@repo_not_backfilled)

        assert_no_changes(
          -> do
            CodeScanningAlertRevision
              .where(repository_id: @repo_not_backfilled.id)
              .order(:id)
              .pluck(:alert_number)
          end
        ) do
          Backfill::CodeScanningAlertNumberJob.perform_now(repository_id: @repo_not_backfilled.id)
        end

        assert_dogstats_distribution 1, "batched_job.time.dist"
      end
    end

    private

    def setup_ts_request(repository, include_initial_revs: false)
      ts_alerts = @alert_numbers.flat_map do |number|
        alert_created_at = @base_date.to_time.utc
        alert_updated_at = alert_created_at + (number % 3).days

        revs = []

        if include_initial_revs
          revs << ::Turboscan::Proto::InsightsAlert.new(
            id: number + @alert_id_mod,
            number:,
            repository_id: repository.id,
            created_at: alert_created_at,
            updated_at: alert_created_at
          )
        end

        revs << ::Turboscan::Proto::InsightsAlert.new(
          id: number + @alert_id_mod,
          number:,
          repository_id: repository.id,
          created_at: alert_created_at,
          updated_at: alert_updated_at
        )

        revs
      end

      ::Turboscan::Proto::InsightsClient.any_instance.expects(:get_alerts_for_insights_backfill).returns(Twirp::ClientResp.new(
        data: ::Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse.new(alerts: ts_alerts)
      ))
    end
  end
end
