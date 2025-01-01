# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class FeatureStatusRevisionTest < GitHub::TestCase
    include DogstatsTestHelpers

    fixtures do
      @biz_1 = create(:business)
      @biz_1_org_1 = create(:organization, business: @biz_1)
      @biz_1_org_2 = create(:organization, business: @biz_1)
      @biz_1_org_1_repo_1 = create(:private_repository, owner: @biz_1_org_1)
      @biz_1_org_1_soa_repo_1 = create(:security_overview_analytics_repository, repository: @biz_1_org_1_repo_1)
    end

    setup do
      SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:report_duplicate_revisions?).returns(false)
    end

    context "#factorybot" do
      test "can create data with defaults" do
        by_bot = create(:security_overview_analytics_feature_status_revision)
        by_model = T.must(FeatureStatusRevision.find_by(id: by_bot.id))
        assert_equal by_model, by_bot
      end
    end

    context "#relations" do
      test "can access ::Repository record" do
        by_bot = create(:security_overview_analytics_feature_status_revision)
        by_model = FeatureStatusRevision.find_by!(id: by_bot.id)

        repo = ::Repositories::Public.find_active!(by_model.repository_id)
        assert_equal repo, by_model.repository
      end

      test "can access Repository record" do
        by_bot = create(:security_overview_analytics_feature_status_revision)
        by_model = FeatureStatusRevision.find_by!(id: by_bot.id)

        repo_metadata = Repository.find_by!(repository_id: by_model.repository_id)
        assert_equal repo_metadata, by_model.repository_metadata
      end

      test "can access Date record" do
        next_revision_date_by_bot = create(:security_overview_analytics_date, date_value: 1.day.after)
        by_bot = create(:security_overview_analytics_feature_status_revision, next_revision_date_id: next_revision_date_by_bot.id)
        by_model = FeatureStatusRevision.find_by!(id: by_bot.id)

        date = Date.find_by!(id: by_model.date_id)
        next_revision_date = Date.find_by!(id: by_model.next_revision_date&.id)
        assert_equal date, by_model.date
        assert_equal next_revision_date, by_model.next_revision_date
      end
    end

    context "#find_deviations" do
      test "returns empty array if there is no deviation" do
        feature_status = create(:security_overview_analytics_feature_status_revision)
        assert feature_status.find_deviations.empty?
      end

      test "returns repo_not_found if repository is not found" do
        feature_status = create(:security_overview_analytics_feature_status_revision)
        feature_status.repository.destroy
        assert_equal :repo_not_found, feature_status.reload.find_deviations.first
      end

      test "returns repo_deleted if repository is not found" do
        feature_status = create(:security_overview_analytics_feature_status_revision)
        feature_status.repository.remove(create(:user))
        assert_equal :repo_deleted, feature_status.reload.find_deviations.first
      end

      test "returns dependabot_alerts_enabled if deviation for the feature status found" do
        ::SecurityProduct::VulnerabilityAlerts.any_instance.stubs(:enabled?).returns(true)
        feature_status = create(:security_overview_analytics_feature_status_revision, dependabot_alerts_enabled: false)
        assert_equal :dependabot_alerts_enabled, feature_status.reload.find_deviations.first
      end

      test "returns dependabot_security_updates_enabled if deviation for the feature status found" do
        ::SecurityProduct::VulnerabilityUpdates.any_instance.stubs(:enabled?).returns(true)
        feature_status = create(:security_overview_analytics_feature_status_revision, dependabot_security_updates_enabled: false)
        assert_equal :dependabot_security_updates_enabled, feature_status.reload.find_deviations.first
      end

      test "returns advanced_security_enabled if deviation for the feature status found" do
        ::SecurityProduct::AdvancedSecurity.any_instance.stubs(:enabled?).returns(true)
        feature_status = create(:security_overview_analytics_feature_status_revision, advanced_security_enabled: false)
        assert_equal :advanced_security_enabled, feature_status.reload.find_deviations.first
      end

      test "returns code_scanning_enabled if deviation for the feature status found" do
        ::Repository.any_instance.stubs(:security_feature_configured?).returns(true)
        feature_status = create(:security_overview_analytics_feature_status_revision, code_scanning_enabled: false)
        assert_equal :code_scanning_enabled, feature_status.reload.find_deviations.first
      end

      test "returns secret_scanning_enabled if deviation for the feature status found" do
        ::SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)
        feature_status = create(:security_overview_analytics_feature_status_revision, secret_scanning_enabled: false)
        assert_equal :secret_scanning_enabled, feature_status.reload.find_deviations.first
      end

      test "returns secret_scanning_push_protection_enabled if deviation for the feature status found" do
        ::SecretScanning::Features::Repo::PushProtection.any_instance.stubs(:enabled?).returns(true)
        feature_status = create(:security_overview_analytics_feature_status_revision, secret_scanning_push_protection_enabled: false)
        assert_equal :secret_scanning_push_protection_enabled, feature_status.reload.find_deviations.first
      end
    end

    context "#upsert_feature_status" do
      test "skips event if the date_id is older than two days ago" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        two_days_ago = create(:security_overview_analytics_date, date_value: 2.days.ago.utc)

        FeatureStatusRevision.upsert_feature_status(
          repository_id: repo.id,
          date_id: two_days_ago.id,
          payload: FeatureStatusRevision::UpdatePayload.new(
            code_scanning_enabled: true,
            dependabot_alerts_enabled: true
          )
        )

        assert_dogstats_increment 1,
          "security_overview_analytics.upsert_feature_status.skipped",
          tags: ["reason:old_date_id"]
      end

      test "reports event if it's a duplicate of the previous one and flag is on" do
        SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:report_duplicate_revisions?).returns(true)

        org = create(:organization)
        repo = create(:repository, owner: org)
        repository_metadata = create(:security_overview_analytics_repository, repository: repo)
        one_day_ago = create(:security_overview_analytics_date, date_value: 1.day.ago.utc)
        today = create(:security_overview_analytics_date, date_value: DateTime.current.utc)

        last_revision = create(
          :security_overview_analytics_feature_status_revision,
          repository_metadata:,
          date_id: one_day_ago.id,
          code_scanning_enabled: false,
          dependabot_alerts_enabled: false,
        )
        assert_equal 1, FeatureStatusRevision.count
        refute last_revision.code_scanning_enabled
        refute last_revision.dependabot_alerts_enabled

        FeatureStatusRevision.upsert_feature_status(
          repository_id: repo.id,
          date_id: today.id,
          payload: FeatureStatusRevision::UpdatePayload.new(
            code_scanning_enabled: false,
            dependabot_alerts_enabled: false
          )
        )

        assert_equal 2, FeatureStatusRevision.count
        refute last_revision.code_scanning_enabled
        refute last_revision.dependabot_alerts_enabled
        assert_dogstats_increment 1,
          "security_overview_analytics.revision_upserter.duplicate_revisions.detected",
          tags: ["feature_type:feature_status"]
      end

      test "creates initial feature status revision if none presents" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        date = create(:security_overview_analytics_date)
        refute FeatureStatusRevision.find_by(repository_id: repo.id, date_id: date.id)

        FeatureStatusRevision.upsert_feature_status(
          repository_id: repo.id,
          date_id: date.id,
          payload: FeatureStatusRevision::UpdatePayload.new(
            code_scanning_enabled: true
          )
        )

        last_revision = FeatureStatusRevision.find_by(repository_id: repo.id, date_id: date.id)
        assert last_revision
        refute last_revision&.dependabot_alerts_enabled
        refute last_revision&.advanced_security_enabled
        refute last_revision&.secret_scanning_enabled
        refute last_revision&.secret_scanning_push_protection_enabled
        assert last_revision&.code_scanning_enabled

        assert_dogstats_increment 1,
          "security_overview_analytics.upsert_feature_status.succeeded",
          tags: ["upsert_scenario:insert_initial_revision"]
      end

      test "updates feature status on existing revision if found on the same date_id" do
        last_revision = create(
          :security_overview_analytics_feature_status_revision,
          code_scanning_enabled: false,
          dependabot_alerts_enabled: false,
        )
        refute last_revision.code_scanning_enabled
        refute last_revision.dependabot_alerts_enabled

        FeatureStatusRevision.upsert_feature_status(
          repository_id: last_revision.repository_id,
          date_id: last_revision.date_id,
          payload: FeatureStatusRevision::UpdatePayload.new(
            code_scanning_enabled: true,
            dependabot_alerts_enabled: true
          )
        )

        assert last_revision.reload.code_scanning_enabled
        assert last_revision.reload.dependabot_alerts_enabled

        assert_dogstats_increment 1,
          "security_overview_analytics.upsert_feature_status.succeeded",
          tags: ["upsert_scenario:update_latest_revision"]
      end

      test "creates new revision from event received with later date_id" do
        today = create(:security_overview_analytics_date)
        yesterday = create(:security_overview_analytics_date, date_value: 1.day.ago.utc)
        prev_revision = create(
          :security_overview_analytics_feature_status_revision,
          date: yesterday,
          code_scanning_enabled: false,
          dependabot_alerts_enabled: true
        )
        refute prev_revision.code_scanning_enabled
        assert prev_revision.dependabot_alerts_enabled
        assert_equal 99991231, prev_revision.next_revision_date_id

        FeatureStatusRevision.upsert_feature_status(
          repository_id: prev_revision.repository_id,
          date_id: today.id,
          payload: FeatureStatusRevision::UpdatePayload.new(
            code_scanning_enabled: true
          )
        )

        refute prev_revision.reload.code_scanning_enabled
        assert prev_revision.dependabot_alerts_enabled
        assert_equal today.id, prev_revision.next_revision_date_id

        last_revision = FeatureStatusRevision.find_by(repository_id: prev_revision.repository_id, date_id: today.id)
        assert last_revision
        assert last_revision&.dependabot_alerts_enabled
        assert last_revision&.code_scanning_enabled
        assert_equal 99991231, last_revision&.next_revision_date_id

        assert_dogstats_increment 1,
          "security_overview_analytics.upsert_feature_status.succeeded",
          tags: ["upsert_scenario:insert_from_latest_revision"]
      end

      test "creates new revision and connects it with previous and next revisions" do
        today = create(:security_overview_analytics_date)
        tomorrow = create(:security_overview_analytics_date, date_value: 1.day.after.utc)
        yesterday = create(:security_overview_analytics_date, date_value: 1.day.ago.utc)
        repo_metadata = create(:security_overview_analytics_repository)
        prev_revision = create(
          :security_overview_analytics_feature_status_revision,
          repository_metadata: repo_metadata,
          date: yesterday,
          next_revision_date_id: tomorrow.id,
          code_scanning_enabled: false,
          dependabot_alerts_enabled: true
        )
        latest_revision = create(
          :security_overview_analytics_feature_status_revision,
          repository_metadata: repo_metadata,
          date: tomorrow,
          code_scanning_enabled: true,
          dependabot_alerts_enabled: false
        )
        refute prev_revision.code_scanning_enabled
        assert prev_revision.dependabot_alerts_enabled
        assert_equal tomorrow.id, prev_revision.next_revision_date_id
        assert latest_revision.code_scanning_enabled
        refute latest_revision.dependabot_alerts_enabled
        assert_equal 99991231, latest_revision.next_revision_date_id

        FeatureStatusRevision.upsert_feature_status(
          repository_id: prev_revision.repository_id,
          date_id: today.id,
          payload: FeatureStatusRevision::UpdatePayload.new(
            code_scanning_enabled: true,
            dependabot_alerts_enabled: true
          )
        )

        current_revision = FeatureStatusRevision.find_by(repository_id: prev_revision.repository_id, date_id: today.id)
        assert current_revision

        refute prev_revision.reload.code_scanning_enabled
        assert prev_revision.dependabot_alerts_enabled
        assert_equal today.id, prev_revision.next_revision_date_id

        assert current_revision&.dependabot_alerts_enabled
        assert current_revision&.code_scanning_enabled
        assert_equal tomorrow.id, current_revision&.next_revision_date_id

        assert latest_revision.reload.code_scanning_enabled
        refute latest_revision.dependabot_alerts_enabled
        assert_equal 99991231, latest_revision.next_revision_date_id

        assert_dogstats_increment 1,
          "security_overview_analytics.upsert_feature_status.succeeded",
          tags: ["upsert_scenario:insert_as_previous_revision"]
      end

      test "updates previous revision in place if event received have the same date_id" do
        today = create(:security_overview_analytics_date)
        yesterday = create(:security_overview_analytics_date, date_value: 1.day.ago.utc)
        repo_metadata = create(:security_overview_analytics_repository)
        prev_revision = create(
          :security_overview_analytics_feature_status_revision,
          repository_metadata: repo_metadata,
          date: yesterday,
          next_revision_date_id: today.id,
          code_scanning_enabled: false,
          dependabot_alerts_enabled: true
        )
        latest_revision = create(
          :security_overview_analytics_feature_status_revision,
          repository_metadata: repo_metadata,
          date: today,
          code_scanning_enabled: true,
          dependabot_alerts_enabled: false
        )
        refute prev_revision.code_scanning_enabled
        assert prev_revision.dependabot_alerts_enabled
        assert_equal today.id, prev_revision.next_revision_date_id
        assert latest_revision.code_scanning_enabled
        refute latest_revision.dependabot_alerts_enabled
        assert_equal 99991231, latest_revision.next_revision_date_id

        FeatureStatusRevision.upsert_feature_status(
          repository_id: prev_revision.repository_id,
          date_id: yesterday.id,
          payload: FeatureStatusRevision::UpdatePayload.new(
            code_scanning_enabled: true
          )
        )

        assert prev_revision.reload.code_scanning_enabled
        assert prev_revision.dependabot_alerts_enabled
        assert_equal today.id, prev_revision.next_revision_date_id

        assert latest_revision.reload.code_scanning_enabled
        refute latest_revision.dependabot_alerts_enabled
        assert_equal 99991231, latest_revision.next_revision_date_id

        assert_dogstats_increment 1,
          "security_overview_analytics.upsert_feature_status.succeeded",
          tags: ["upsert_scenario:update_previous_revision"]
      end

      test "retries once if raises ActiveRecord::RecordNotUnique" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        date = create(:security_overview_analytics_date)
        FeatureStatusRevision.stubs(:transaction).raises(ActiveRecord::RecordNotUnique)

        assert_raises ActiveRecord::RecordNotUnique do
          FeatureStatusRevision.upsert_feature_status(
            repository_id: repo.id,
            date_id: date.id,
            payload: FeatureStatusRevision::UpdatePayload.new(
              code_scanning_enabled: true
            )
          )
        end

        assert_dogstats_increment 1, "security_overview_analytics.upsert_feature_status.retried"
      end
    end

    context "#delete_by_repository_ids" do
      test "deletes all revisions on a repository" do
        now = Time.now
        repository_id = 1
        alert_number = 1

        [
          create(:security_overview_analytics_date, date_value: now),
          create(:security_overview_analytics_date, date_value: now - 1.day)
        ].reduce(Date::FUTURE_DATE_ID) do |next_date_id, date|
          create(
            :security_overview_analytics_feature_status_revision,
            repository_id:,
            date: date,
            next_revision_date_id: next_date_id,
          )
          create(
            :security_overview_analytics_feature_status_revision,
            repository_id: repository_id + 1,
            date: date,
            next_revision_date_id: next_date_id,
          )
          create(
            :security_overview_analytics_feature_status_revision,
            repository_id: repository_id + 2,
            date: date,
            next_revision_date_id: next_date_id,
          )
          next date.id
        end
        repo1_revisions = FeatureStatusRevision.where(repository_id: repository_id).pluck(:id).uniq
        repo2_revisions = FeatureStatusRevision.where(repository_id: repository_id + 1).pluck(:id).uniq
        repo3_revisions = FeatureStatusRevision.where(repository_id: repository_id + 2).pluck(:id).uniq
        assert_equal 2, repo1_revisions.size
        assert_equal 2, repo2_revisions.size
        assert_equal 2, repo3_revisions.size

        FeatureStatusRevision.delete_by_repository_ids([repository_id, repository_id + 1])

        assert_empty FeatureStatusRevision.where(repository_id: [repository_id, repository_id + 1]).to_a
        assert_dogstats_count_value 4, "security_overview_analytics.feature_status_revisions.deleted"

        repo3_revisions = FeatureStatusRevision.where(repository_id: repository_id + 2).pluck(:id).uniq
        assert_equal 2, repo3_revisions.size
      end
    end

    context "#compress_revisions" do
      test "removes duplicate revisions and leaves latest revision unchanged" do
        repository_id = @biz_1_org_1_soa_repo_1.id

        dates = [
          create(:security_overview_analytics_date, date_value: Time.parse("2023-09-17")),
          create(:security_overview_analytics_date, date_value: Time.parse("2023-09-14")), # simulate gap
          create(:security_overview_analytics_date, date_value: Time.parse("2023-09-13")),
          create(:security_overview_analytics_date, date_value: Time.parse("2023-09-12")),
        ]

        dates.reduce(Date::FUTURE_DATE_ID) do |next_date_id, date|
          create(
            :security_overview_analytics_feature_status_revision,
            date: date,
            next_revision_date_id: next_date_id,
            repository_metadata: @biz_1_org_1_soa_repo_1,
          )
          next date.id
        end

        model = FeatureStatusRevision
        assert_equal 4, FeatureStatusRevision.count

        model.compress_revisions(repository_id:)
        assert_equal 2, FeatureStatusRevision.count
        assert FeatureStatusRevision.where(repository_id:, next_revision_date_id: Date::FUTURE_DATE_ID).exists?
      end

      test "does not remove duplicate revisions in dry run mode" do
        repo = create(:private_repository, owner: @biz_1_org_1)
        soa_repo = create(:security_overview_analytics_repository, repository: repo)

        dates = [
          create(:security_overview_analytics_date, date_value: Time.parse("2023-01-17")),
          create(:security_overview_analytics_date, date_value: Time.parse("2023-01-14")), # simulate gap
          create(:security_overview_analytics_date, date_value: Time.parse("2023-01-13")),
          create(:security_overview_analytics_date, date_value: Time.parse("2023-01-12")),
        ]

        dates.reduce(Date::FUTURE_DATE_ID) do |next_date_id, date|
          create(
            :security_overview_analytics_feature_status_revision,
            date: date,
            next_revision_date_id: next_date_id,
            repository_metadata: soa_repo,
          )
          next date.id
        end

        model = FeatureStatusRevision
        assert_equal 4, FeatureStatusRevision.count

        model.compress_revisions(repository_id: repo.id, dry_run: true)
        assert_equal 4, FeatureStatusRevision.count
      end

      test "does not remove revisions that occured in the last two weeks" do
        repository_id = @biz_1_org_1_soa_repo_1.id

        dates = [
          create(:security_overview_analytics_date, date_value: ::Date.current - 1.day), # latest revision; will not be removed
          create(:security_overview_analytics_date, date_value: ::Date.current - 2.days), # this will not be removed
          create(:security_overview_analytics_date, date_value: ::Date.current - 15.days), # this will be removed
          create(:security_overview_analytics_date, date_value: ::Date.current - 17.days),
        ]

        dates.reduce(Date::FUTURE_DATE_ID) do |next_date_id, date|
          create(
            :security_overview_analytics_feature_status_revision,
            date: date,
            next_revision_date_id: next_date_id,
            repository_metadata: @biz_1_org_1_soa_repo_1,
          )
          next date.id
        end

        model = FeatureStatusRevision
        assert_equal 4, FeatureStatusRevision.where(repository_id:).count
        model.compress_revisions(repository_id:)
        assert_equal 3, FeatureStatusRevision.where(repository_id:).count
      end

      test "does not remove revisions if there are no duplicates" do
        repository_id = @biz_1_org_1_soa_repo_1.id

        dates = [
          create(:security_overview_analytics_date, date_value: Time.parse("2023-10-12")),
          create(:security_overview_analytics_date, date_value: Time.parse("2023-10-13")),
          create(:security_overview_analytics_date, date_value: Time.parse("2023-10-14")), # simulate gap
          create(:security_overview_analytics_date, date_value: Time.parse("2023-10-17")),
        ]

        dates.each_with_index do |date, idx|
          create(
            :security_overview_analytics_feature_status_revision,
            date: date,
            next_revision_date_id: dates[idx + 1]&.id || Date::FUTURE_DATE_ID,
            repository_metadata: @biz_1_org_1_soa_repo_1,
            dependabot_alerts_enabled: idx.even? ? false : true,
          )
        end

        model = FeatureStatusRevision
        assert_equal 4, FeatureStatusRevision.where(repository_id:).count
        model.compress_revisions(repository_id:)
        assert_equal 4, FeatureStatusRevision.where(repository_id:).count
      end
    end

    context "#timestamps" do
      test "are stored in utc" do
        now = Time.now
        model = create(
          :security_overview_analytics_feature_status_revision,
          created_at: now,
          updated_at: now
        )
        assert model.created_at&.utc?
        assert_timestamp now.utc, model.created_at
        assert model.updated_at&.utc?
        assert_timestamp now.utc, model.updated_at
      end
    end

    private def assert_timestamp(expected, actual)
      assert_equal expected.to_i, actual.to_i
      assert_equal expected.usec, actual.usec
    end
  end
end
