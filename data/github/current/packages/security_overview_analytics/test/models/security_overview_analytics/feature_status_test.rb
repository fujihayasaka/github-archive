# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class FeatureStatusTest < GitHub::TestCase
    include SecurityOverviewAnalytics::TestFixtures

    fixtures do
      @owner = create(:user)
      @org = create(:organization, admin: @owner)
      @repo = create(:repository, owner: @org)
    end

    context "#factorybot" do
      test "can create data with defaults" do
        by_bot = create(:soa_feature_status)
        by_model = T.must(FeatureStatus.find_by(repository_id: by_bot.repository_id))
        assert_equal by_model, by_bot
      end
    end

    context "#relations" do
      test "can access ::Repository record" do
        by_bot = create(:soa_feature_status)
        by_model = FeatureStatus.find_by!(repository_id: by_bot.repository_id)

        repo = ::Repositories::Public.find_active!(T.must(by_model.repository_id))
        assert_equal repo, by_model.repository
      end

      test "can access Repository record" do
        by_bot = create(:soa_feature_status)
        by_model = FeatureStatus.find_by!(repository_id: by_bot.repository_id)

        repo_metadata = Repository.find_by!(repository_id: by_model.repository_id)
        assert_equal repo_metadata, by_model.repository_metadata
      end
    end

    context ".update_summary" do
      context "when record already exists" do
        test "updates the existing FeatureStatus record" do
          create(:soa_feature_status, repository: @repo, updated_at: 2.days.ago)

          # give it some reason to update the summary
          create(:soa_feature_status_revision, repository: @repo, advanced_security_enabled: true)

          now = Time.current.utc
          Timecop.freeze(now) do
            FeatureStatus.update_summary(repository_id: @repo.id)
          end

          record = FeatureStatus.find_by(repository_id: @repo.id)
          refute_nil record
          record = T.cast(record, FeatureStatus)
          assert_equal now.to_i, record.updated_at&.utc&.to_i
        end
      end

      context "when record does not exist" do
        test "creates a new FeatureStatus record" do
          assert_nil FeatureStatus.find_by(repository_id: @repo.id)

          now = Time.current.utc
          Timecop.freeze(now) do
            FeatureStatus.update_summary(repository_id: @repo.id)
          end

          record = FeatureStatus.find_by(repository_id: @repo.id)
          refute_nil record
          record = T.cast(record, FeatureStatus)
          assert_equal now.to_i, record.created_at&.utc&.to_i
          assert_equal now.to_i, record.updated_at&.utc&.to_i
        end
      end

      context "when repository has no alert or feature revisions" do
        test "populates with default values" do
          assert_nil FeatureStatusRevision.find_by(repository_id: @repo.id)
          assert_nil DependabotAlertRevision.find_by(repository_id: @repo.id)
          assert_nil CodeScanningAlertRevision.find_by(repository_id: @repo.id)
          assert_nil SecretScanningAlertRevision.find_by(repository_id: @repo.id)

          FeatureStatus.update_summary(repository_id: @repo.id)

          record = FeatureStatus.find_by(repository_id: @repo.id)
          refute_nil record
          record = T.cast(record, FeatureStatus)

          assert_equal "NOT_ENABLED", record.advanced_security_status
          assert_equal "NOT_ENABLED", record.dependabot_alerts_status
          assert_equal 0, record.dependabot_alerts_total_count
          assert_equal 0, record.dependabot_alerts_critical_count
          assert_equal 0, record.dependabot_alerts_high_count
          assert_equal 0, record.dependabot_alerts_medium_count
          assert_equal 0, record.dependabot_alerts_low_count
          assert_equal "NOT_ENABLED", record.code_scanning_alerts_status
          assert_equal 0, record.code_scanning_alerts_total_count
          assert_equal 0, record.code_scanning_alerts_critical_count
          assert_equal 0, record.code_scanning_alerts_high_count
          assert_equal 0, record.code_scanning_alerts_medium_count
          assert_equal 0, record.code_scanning_alerts_low_count
          assert_equal 0, record.code_scanning_alerts_info_count
          assert_equal "NOT_ENABLED", record.secret_scanning_alerts_status
          assert_equal 0, record.secret_scanning_alerts_total_count
          assert_equal "NOT_ENABLED", record.dependabot_security_updates_status
          assert_equal "NOT_ENABLED", record.dependabot_version_updates_status
          assert_equal "NOT_ELIGIBLE", record.code_scanning_auto_codeql_status
          assert_equal "NOT_ENABLED", record.code_scanning_pr_reviews_status
          assert_equal "NOT_ENABLED", record.secret_scanning_push_protection_status
        end
      end

      context "when repository has alert and feature revisions" do
        test "populates with rollup data" do
          create_repo_alerts(repository: @repo)
          refute_nil FeatureStatusRevision.find_by(repository_id: @repo.id)
          refute_nil DependabotAlertRevision.find_by(repository_id: @repo.id)
          refute_nil CodeScanningAlertRevision.find_by(repository_id: @repo.id)
          refute_nil SecretScanningAlertRevision.find_by(repository_id: @repo.id)

          FeatureStatus.update_summary(repository_id: @repo.id)

          record = FeatureStatus.find_by(repository_id: @repo.id)
          refute_nil record
          record = T.cast(record, FeatureStatus)

          assert_equal "NOT_ENABLED", record.advanced_security_status
          assert_equal "ENABLED", record.dependabot_alerts_status
          assert_equal 4, record.dependabot_alerts_total_count
          assert_equal 1, record.dependabot_alerts_critical_count
          assert_equal 1, record.dependabot_alerts_high_count
          assert_equal 1, record.dependabot_alerts_medium_count
          assert_equal 1, record.dependabot_alerts_low_count
          assert_equal "ENABLED", record.code_scanning_alerts_status
          assert_equal 5, record.code_scanning_alerts_total_count
          assert_equal 1, record.code_scanning_alerts_critical_count
          assert_equal 1, record.code_scanning_alerts_high_count
          assert_equal 1, record.code_scanning_alerts_medium_count
          assert_equal 1, record.code_scanning_alerts_low_count
          assert_equal 1, record.code_scanning_alerts_info_count
          assert_equal "ENABLED", record.secret_scanning_alerts_status
          assert_equal 1, record.secret_scanning_alerts_total_count
          assert_equal "NOT_ENABLED", record.dependabot_security_updates_status
          assert_equal "NOT_ENABLED", record.dependabot_version_updates_status
          assert_equal "NOT_ELIGIBLE", record.code_scanning_auto_codeql_status
          assert_equal "NOT_ENABLED", record.code_scanning_pr_reviews_status
          assert_equal "NOT_ENABLED", record.secret_scanning_push_protection_status
        end

        test "only includes alert counts for enabled features" do
          create_repo_alerts(repository: @repo)
          feature_status_revision = FeatureStatusRevision.find_by!(repository_id: @repo.id, next_revision_date_id: Date::FUTURE_DATE_ID)

          # all disabled
          feature_status_revision.update!(dependabot_alerts_enabled: false, code_scanning_enabled: false, secret_scanning_enabled: false)
          FeatureStatus.update_summary(repository_id: @repo.id)
          feature_status = FeatureStatus.find_by!(repository_id: @repo.id)
          assert_equal 0, feature_status.dependabot_alerts_total_count
          assert_equal 0, feature_status.code_scanning_alerts_total_count
          assert_equal 0, feature_status.secret_scanning_alerts_total_count

          # dependabot enabled
          feature_status_revision.update!(dependabot_alerts_enabled: true, code_scanning_enabled: false, secret_scanning_enabled: false)
          FeatureStatus.update_summary(repository_id: @repo.id)
          feature_status = FeatureStatus.find_by!(repository_id: @repo.id)
          assert_equal 4, feature_status.dependabot_alerts_total_count
          assert_equal 0, feature_status.code_scanning_alerts_total_count
          assert_equal 0, feature_status.secret_scanning_alerts_total_count

          # code scanning enabled
          feature_status_revision.update!(dependabot_alerts_enabled: false, code_scanning_enabled: true, secret_scanning_enabled: false)
          FeatureStatus.update_summary(repository_id: @repo.id)
          feature_status = FeatureStatus.find_by!(repository_id: @repo.id)
          assert_equal 0, feature_status.dependabot_alerts_total_count
          assert_equal 5, feature_status.code_scanning_alerts_total_count
          assert_equal 0, feature_status.secret_scanning_alerts_total_count

          # secret scanning enabled
          feature_status_revision.update!(dependabot_alerts_enabled: false, code_scanning_enabled: false, secret_scanning_enabled: true)
          FeatureStatus.update_summary(repository_id: @repo.id)
          feature_status = FeatureStatus.find_by!(repository_id: @repo.id)
          assert_equal 0, feature_status.dependabot_alerts_total_count
          assert_equal 0, feature_status.code_scanning_alerts_total_count
          assert_equal 1, feature_status.secret_scanning_alerts_total_count
        end

        test "handles auto codeql eligibility states" do
          repository_metadata = create(:soa_repository, repository: @repo)
          feature_status_revision = create(:soa_feature_status_revision, repository_metadata:)

          # enabled
          feature_status_revision.update!(code_scanning_auto_codeql_enabled: true, code_scanning_auto_codeql_eligible: true)
          FeatureStatus.update_summary(repository_id: @repo.id)
          assert FeatureStatus.find_by(repository_id: @repo.id, code_scanning_auto_codeql_status: "ENABLED")

          # eligible
          feature_status_revision.update!(code_scanning_auto_codeql_enabled: false, code_scanning_auto_codeql_eligible: true)
          FeatureStatus.update_summary(repository_id: @repo.id)
          assert FeatureStatus.find_by(repository_id: @repo.id, code_scanning_auto_codeql_status: "ELIGIBLE")

          # not eligible
          feature_status_revision.update!(code_scanning_auto_codeql_enabled: false, code_scanning_auto_codeql_eligible: false)
          FeatureStatus.update_summary(repository_id: @repo.id)
          assert FeatureStatus.find_by(repository_id: @repo.id, code_scanning_auto_codeql_status: "NOT_ELIGIBLE")
        end
      end
    end
  end
end
