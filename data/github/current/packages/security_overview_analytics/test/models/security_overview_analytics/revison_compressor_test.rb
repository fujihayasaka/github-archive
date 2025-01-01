# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class RevisionCompressorTest < GitHub::TestCase
    include DogstatsTestHelpers

    fixtures do
      @biz_1 = create(:business)
      @biz_1_org_1 = create(:organization, business: @biz_1)
      @biz_1_org_2 = create(:organization, business: @biz_1)
      @biz_1_org_1_repo_1 = create(:private_repository, owner: @biz_1_org_1)
      @biz_1_org_1_soa_repo_1 = create(:security_overview_analytics_repository, repository: @biz_1_org_1_repo_1)

      @dates = [
        create(:security_overview_analytics_date, date_value: Time.parse("2023-09-17")),
        create(:security_overview_analytics_date, date_value: Time.parse("2023-09-14")), # simulate gap
        create(:security_overview_analytics_date, date_value: Time.parse("2023-09-13")),
        create(:security_overview_analytics_date, date_value: Time.parse("2023-09-12")),
      ]
    end

    setup do
      @dates.reduce(Date::FUTURE_DATE_ID) do |next_date_id, date|
        create(
          :security_overview_analytics_dependabot_alert_revision,
          alert_number: 1,
          alert_created_at: @dates.last.date_value,
          alert_updated_at: @dates.last.date_value,
          date: date,
          next_revision_date_id: next_date_id,
          repository_metadata: @biz_1_org_1_soa_repo_1,
        )
        create(
          :security_overview_analytics_code_scanning_alert_revision,
          alert_number: 1,
          alert_created_at: @dates.last.date_value,
          alert_updated_at: @dates.last.date_value,
          date: date,
          next_revision_date_id: next_date_id,
          repository_metadata: @biz_1_org_1_soa_repo_1,
        )
        create(
          :security_overview_analytics_secret_scanning_alert_revision,
          alert_type: "3adde576-d108-4845-85eb-bc5526da1a5d",
          alert_type_provider: "42095bb8-fe4a-4efe-8c8e-d74f74777c9f",
          alert_type_slug: "533bb433-a634-4123-8508-b3150f0fcc26",
          alert_number: 1,
          alert_created_at: @dates.last.date_value,
          alert_updated_at: @dates.last.date_value,
          date: date,
          next_revision_date_id: next_date_id,
          repository_metadata: @biz_1_org_1_soa_repo_1,
        )
        next date.id
      end
    end

    context "#compress_revisions" do
      context "DependabotAlertRevision" do
        test "removes duplicate revisions and leaves latest revision unchanged" do
          repository_id = @biz_1_org_1_soa_repo_1.id
          alert_number = 1

          dbot = DependabotAlertRevision
          assert_equal 4, DependabotAlertRevision.count

          dbot.compress_revisions(repository_id:, alert_number:)
          assert_equal 2, DependabotAlertRevision.count
          assert DependabotAlertRevision.where(alert_number: 1, next_revision_date_id: Date::FUTURE_DATE_ID).exists?
        end

        test "does not remove duplicate revisions on dry run" do
          repository_id = @biz_1_org_1_soa_repo_1.id
          alert_number = 2

          dbot = DependabotAlertRevision
          assert_equal 4, DependabotAlertRevision.count

          dbot.compress_revisions(repository_id:, alert_number:, dry_run: true)
          assert_equal 4, DependabotAlertRevision.count
        end

        test "does not remove revisions that occured in the last two weeks" do
          repository_id = @biz_1_org_1_soa_repo_1.id
          alert_number = 3

          dates = [
            create(:security_overview_analytics_date, date_value: ::Date.current - 1.day), # latest revision; will not be removed
            create(:security_overview_analytics_date, date_value: ::Date.current - 2.days), # this will not be removed
            create(:security_overview_analytics_date, date_value: ::Date.current - 15.days), # this will be removed
            create(:security_overview_analytics_date, date_value: ::Date.current - 17.days),
          ]

          dates.reduce(Date::FUTURE_DATE_ID) do |next_date_id, date|
            create(
              :security_overview_analytics_dependabot_alert_revision,
              alert_number:,
              alert_created_at: dates.last.date_value,
              alert_updated_at: dates.last.date_value,
              date: date,
              next_revision_date_id: next_date_id,
              repository_metadata: @biz_1_org_1_soa_repo_1,
            )
            next date.id
          end

          dbot = DependabotAlertRevision
          assert_equal 4, DependabotAlertRevision.where(repository_id:, alert_number:).count
          dbot.compress_revisions(repository_id:, alert_number:)
          assert_equal 3, DependabotAlertRevision.where(repository_id:, alert_number:).count
        end

        test "does not remove revisions if there are no duplicates" do
          repository_id = @biz_1_org_1_soa_repo_1.id
          alert_number = 4

          dates = [
            create(:security_overview_analytics_date, date_value: Time.parse("2023-10-12")),
            create(:security_overview_analytics_date, date_value: Time.parse("2023-10-13")),
            create(:security_overview_analytics_date, date_value: Time.parse("2023-10-14")), # simulate gap
            create(:security_overview_analytics_date, date_value: Time.parse("2023-10-17")),
          ]

          dates.each_with_index do |date, idx|
            create(
              :security_overview_analytics_dependabot_alert_revision,
              alert_number:,
              alert_created_at: dates.first.date_value,
              alert_updated_at: date.date_value,
              date: date,
              next_revision_date_id: dates[idx + 1]&.id || Date::FUTURE_DATE_ID,
              repository_metadata: @biz_1_org_1_soa_repo_1,
              alert_resolved: idx.even? ? false : true,
            )
          end

          dbot = DependabotAlertRevision
          assert_equal 4, DependabotAlertRevision.where(repository_id:, alert_number:).count
          dbot.compress_revisions(repository_id:, alert_number:)
          assert_equal 4, DependabotAlertRevision.where(repository_id:, alert_number:).count
        end
      end

      context "CodeScanningAlertRevision" do
        test "removes duplicate revisions and leaves latest revision unchanged" do
          repository_id = @biz_1_org_1_soa_repo_1.id
          alert_number = 1

          cs = CodeScanningAlertRevision
          assert_equal 4, CodeScanningAlertRevision.count

          cs.compress_revisions(repository_id:, alert_number:)
          assert_equal 2, CodeScanningAlertRevision.count
          assert CodeScanningAlertRevision.where(alert_number: 1, next_revision_date_id: Date::FUTURE_DATE_ID).exists?
        end

        test "does not remove duplicate revisions on dry run" do
          repository_id = @biz_1_org_1_soa_repo_1.id
          alert_number = 2

          cs = CodeScanningAlertRevision
          assert_equal 4, CodeScanningAlertRevision.count

          cs.compress_revisions(repository_id:, alert_number:, dry_run: true)
          assert_equal 4, CodeScanningAlertRevision.count
        end

        test "does not remove revisions that occurred in the last two weeks" do
          repository_id = @biz_1_org_1_soa_repo_1.id
          alert_number = 3

          dates = [
            create(:security_overview_analytics_date, date_value: ::Date.current - 1.day),
            create(:security_overview_analytics_date, date_value: ::Date.current - 2.days),
            create(:security_overview_analytics_date, date_value: ::Date.current - 15.days),
            create(:security_overview_analytics_date, date_value: ::Date.current - 17.days),
          ]

          dates.reduce(Date::FUTURE_DATE_ID) do |next_date_id, date|
            create(
              :security_overview_analytics_code_scanning_alert_revision,
              alert_number:,
              alert_created_at: dates.last.date_value,
              alert_updated_at: dates.last.date_value,
              date: date,
              next_revision_date_id: next_date_id,
              repository_metadata: @biz_1_org_1_soa_repo_1,
            )
            next date.id
          end

          cs = CodeScanningAlertRevision
          assert_equal 4, CodeScanningAlertRevision.where(repository_id:, alert_number:).count
          cs.compress_revisions(repository_id:, alert_number:)
          assert_equal 3, CodeScanningAlertRevision.where(repository_id:, alert_number:).count
        end

        test "does not remove revisions if there are no duplicates" do
          repository_id = @biz_1_org_1_soa_repo_1.id
          alert_number = 4

          dates = [
            create(:security_overview_analytics_date, date_value: Time.parse("2023-10-12")),
            create(:security_overview_analytics_date, date_value: Time.parse("2023-10-13")),
            create(:security_overview_analytics_date, date_value: Time.parse("2023-10-14")), # simulate gap
            create(:security_overview_analytics_date, date_value: Time.parse("2023-10-17")),
          ]

          dates.each_with_index do |date, idx|
            create(
              :security_overview_analytics_code_scanning_alert_revision,
              alert_number: 4,
              alert_created_at: dates.first.date_value,
              alert_updated_at: date.date_value,
              date: date,
              next_revision_date_id: dates[idx + 1]&.id || Date::FUTURE_DATE_ID,
              repository_metadata: @biz_1_org_1_soa_repo_1,
              alert_resolved: idx.even? ? false : true,
            )
          end

          cs = CodeScanningAlertRevision
          assert_equal 4, CodeScanningAlertRevision.where(repository_id:, alert_number:).count
          cs.compress_revisions(repository_id:, alert_number:)
          assert_equal 4, CodeScanningAlertRevision.where(repository_id:, alert_number:).count
        end
      end

      context "SecretScanningAlertRevision" do
        test "removes duplicate revisions and leaves latest revision unchanged" do
          repository_id = @biz_1_org_1_soa_repo_1.id
          alert_number = 1

          ss = SecretScanningAlertRevision
          assert_equal 4, SecretScanningAlertRevision.count

          ss.compress_revisions(repository_id:, alert_number:)
          assert_equal 2, SecretScanningAlertRevision.count
          assert SecretScanningAlertRevision.where(alert_number: 1, next_revision_date_id: Date::FUTURE_DATE_ID).exists?
        end

        test "does not remove duplicate revisions on dry run" do
          repository_id = @biz_1_org_1_soa_repo_1.id
          alert_number = 2

          ss = SecretScanningAlertRevision
          assert_equal 4, SecretScanningAlertRevision.count

          ss.compress_revisions(repository_id:, alert_number:, dry_run: true)
          assert_equal 4, SecretScanningAlertRevision.count
        end


        test "does not remove revisions that occurred in the last two weeks" do
          repository_id = @biz_1_org_1_soa_repo_1.id
          alert_number = 3

          dates = [
            create(:security_overview_analytics_date, date_value: ::Date.current - 1.day),
            create(:security_overview_analytics_date, date_value: ::Date.current - 2.days),
            create(:security_overview_analytics_date, date_value: ::Date.current - 15.days),
            create(:security_overview_analytics_date, date_value: ::Date.current - 17.days),
          ]

          dates.reduce(Date::FUTURE_DATE_ID) do |next_date_id, date|
            create(
              :security_overview_analytics_secret_scanning_alert_revision,
              alert_type: "5adde576-d108-4845-85eb-bc5526da1a5d",
              alert_type_provider: "52095bb8-fe4a-4efe-8c8e-d74f74777c9f",
              alert_type_slug: "553bb433-a634-4123-8508-b3150f0fcc26",
              alert_number: 3,
              alert_created_at: @dates.last.date_value,
              alert_updated_at: @dates.last.date_value,
              date: date,
              next_revision_date_id: next_date_id,
              repository_metadata: @biz_1_org_1_soa_repo_1,
            )
            next date.id
          end

          ss = SecretScanningAlertRevision
          assert_equal 4, SecretScanningAlertRevision.where(repository_id:, alert_number:).count
          ss.compress_revisions(repository_id:, alert_number:)
          assert_equal 3, SecretScanningAlertRevision.where(repository_id:, alert_number:).count
        end

        test "does not remove revisions if there are no duplicates" do
          repository_id = @biz_1_org_1_soa_repo_1.id
          alert_number = 4

          dates = [
            create(:security_overview_analytics_date, date_value: Time.parse("2023-10-12")),
            create(:security_overview_analytics_date, date_value: Time.parse("2023-10-13")),
            create(:security_overview_analytics_date, date_value: Time.parse("2023-10-14")), # simulate gap
            create(:security_overview_analytics_date, date_value: Time.parse("2023-10-17")),
          ]

          dates.each_with_index do |date, idx|
            create(
              :security_overview_analytics_secret_scanning_alert_revision,
              alert_number: 4,
              alert_created_at: dates.first.date_value,
              alert_updated_at: date.date_value,
              date: date,
              next_revision_date_id: dates[idx + 1]&.id || Date::FUTURE_DATE_ID,
              repository_metadata: @biz_1_org_1_soa_repo_1,
              alert_resolved: idx.even? ? false : true,
            )
          end

          ss = SecretScanningAlertRevision
          assert_equal 4, SecretScanningAlertRevision.where(repository_id:, alert_number:).count
          ss.compress_revisions(repository_id:, alert_number:)
          assert_equal 4, SecretScanningAlertRevision.where(repository_id:, alert_number:).count
        end
      end
    end
  end
end
