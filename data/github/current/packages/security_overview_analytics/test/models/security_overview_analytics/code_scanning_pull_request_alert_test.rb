# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class CodeScanningPullRequestAlertTest < GitHub::TestCase
    include DogstatsTestHelpers

    # This allow me to prepare sample refs during fixture instead of setup
    self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures

    fixtures do
      @user = create(:user)
      @org = create(:organization, admin: @user)
      @repo = create(:repository, owner: @org, admin: @user, from_example: :simple)

      @master_head = @repo.heads.find_or_build("master")
      @topic_branch_head_ref = @repo.heads.create("topic", @master_head.target, @user)
      @topic_branch_head_ref.append_commit({ message: "some changes", committer: @user }, @user) do |files|
        files.add("file001", "foo")
      end

      # Merged PR will be included in fanout
      @pull = create(:pull_request,
        repository: @repo,
        base_repository: @repo,
        base_user: @user,
        base_ref: @repo.default_branch,
        head_repository: @repo,
        head_user: @user,
        head_ref: @topic_branch_head_ref.name,
        user: @user,
      )
      @pull.merge(@user, message_title: "msg", message: "body")
      @pull.reload
    end

    context "#upsert" do
      test "creates new record" do
        now = Time.now
        payload = CodeScanningPullRequestAlert::UpdatePayload.new(
          repository_id: 1,
          alert_number: 2,
          pull_request_id: 3,
          analysis_id: 4,
          ref: "refs/heads/pr",
          tool: "CodeQL",
          rule_sarif_identifier: "woof",
          alert_created_at: now - 10.days,
          alert_updated_at: now,
          alert_resolved_at: now,
          alert_severity: "CRITICAL",
          alert_resolved: true,
          alert_resolution: 1,
          has_dfa: true,
          has_dfa_comments: true,
          has_autofix: true,
          autofix_accepted: true
        )
        assert_nil CodeScanningPullRequestAlert.find_by(
          repository_id: payload.repository_id,
          alert_number: payload.alert_number,
          pull_request_id: payload.pull_request_id
        )

        CodeScanningPullRequestAlert.upsert(payload)
        validate_table_row_with_payload(payload)

        refute_dogstats_increment "security_overview_analytics.code_scanning_pull_request_alert.unexpected_state"
      end

      test "updates existing record" do
        existing_alert = create(:soa_code_scanning_pr_alert)
        updated_at = existing_alert.updated_at
        refute existing_alert.autofix_accepted

        new_alert_updated_at = existing_alert.alert_updated_at + 1.day
        payload = CodeScanningPullRequestAlert::UpdatePayload.new(
          repository_id: existing_alert.repository_id,
          alert_number: existing_alert.alert_number,
          pull_request_id: existing_alert.pull_request_id,
          analysis_id: existing_alert.analysis_id,
          autofix_accepted: true,
          ref: existing_alert.ref,
          tool: existing_alert.tool,
          rule_sarif_identifier: existing_alert.rule_sarif_identifier,
          alert_created_at: existing_alert.alert_created_at,
          alert_updated_at: new_alert_updated_at,
          alert_resolved_at: existing_alert.alert_resolved_at,
          alert_severity: existing_alert.alert_severity,
          alert_resolved: existing_alert.alert_resolved,
          alert_resolution: existing_alert.alert_resolution
        )

        CodeScanningPullRequestAlert.upsert(payload)
        assert existing_alert.reload.updated_at > updated_at
        assert existing_alert.autofix_accepted

        refute_dogstats_increment "security_overview_analytics.code_scanning_pull_request_alert.unexpected_state"
      end

      test "does not update columns specified in update_except input" do
        existing_alert = create(:soa_code_scanning_pr_alert)
        updated_at = existing_alert.updated_at
        refute existing_alert.alert_resolved

        new_alert_updated_at = existing_alert.alert_updated_at + 1.day
        payload = CodeScanningPullRequestAlert::UpdatePayload.new(
          repository_id: existing_alert.repository_id,
          alert_number: existing_alert.alert_number,
          pull_request_id: existing_alert.pull_request_id,
          analysis_id: existing_alert.analysis_id,
          ref: existing_alert.ref,
          tool: existing_alert.tool,
          rule_sarif_identifier: existing_alert.rule_sarif_identifier,
          alert_created_at: existing_alert.alert_created_at,
          alert_updated_at: new_alert_updated_at,
          alert_resolved_at: existing_alert.alert_resolved_at,
          alert_severity: existing_alert.alert_severity,
          alert_resolved: true,
          alert_resolution: existing_alert.alert_resolution
        )

        CodeScanningPullRequestAlert.upsert(payload, update_except: ["alert_resolved"])
        assert existing_alert.reload.updated_at > updated_at
        refute existing_alert.alert_resolved
      end

      test "does not update existing record if alert_updated_at is the same" do
        existing_alert = create(:soa_code_scanning_pr_alert)
        updated_at = existing_alert.updated_at
        refute existing_alert.alert_resolved

        payload = CodeScanningPullRequestAlert::UpdatePayload.new(
          repository_id: existing_alert.repository_id,
          alert_number: existing_alert.alert_number,
          pull_request_id: existing_alert.pull_request_id,
          analysis_id: existing_alert.analysis_id,
          ref: existing_alert.ref,
          tool: existing_alert.tool,
          rule_sarif_identifier: existing_alert.rule_sarif_identifier,
          alert_created_at: existing_alert.alert_created_at,
          alert_updated_at: existing_alert.alert_updated_at,
          alert_resolved_at: existing_alert.alert_resolved_at,
          alert_severity: existing_alert.alert_severity,
          alert_resolved: true,
          alert_resolution: existing_alert.alert_resolution
        )

        CodeScanningPullRequestAlert.upsert(payload)
        refute existing_alert.reload.updated_at > updated_at
        refute existing_alert.alert_resolved
      end

      test "updates existing record when alert_updated_at is the same if force rewrite" do
        existing_alert = create(:soa_code_scanning_pr_alert)
        updated_at = existing_alert.updated_at
        refute existing_alert.alert_resolved

        payload = CodeScanningPullRequestAlert::UpdatePayload.new(
          repository_id: existing_alert.repository_id,
          alert_number: existing_alert.alert_number,
          pull_request_id: existing_alert.pull_request_id,
          analysis_id: existing_alert.analysis_id,
          ref: existing_alert.ref,
          tool: existing_alert.tool,
          rule_sarif_identifier: existing_alert.rule_sarif_identifier,
          alert_created_at: existing_alert.alert_created_at,
          alert_updated_at: existing_alert.alert_updated_at,
          alert_resolved_at: existing_alert.alert_resolved_at,
          alert_severity: existing_alert.alert_severity,
          alert_resolved: true,
          alert_resolution: existing_alert.alert_resolution
        )

        CodeScanningPullRequestAlert.upsert(payload, force_rewrite: true)
        assert existing_alert.reload.updated_at > updated_at
        assert existing_alert.alert_resolved
      end

      test "retries if it fails to insert a record that already exists" do
        existing_alert = create(:soa_code_scanning_pr_alert)
        new_alert_updated_at = existing_alert.alert_updated_at + 1.day
        payload = CodeScanningPullRequestAlert::UpdatePayload.new(
          repository_id: existing_alert.repository_id,
          alert_number: existing_alert.alert_number,
          pull_request_id: existing_alert.pull_request_id,
          analysis_id: existing_alert.analysis_id,
          ref: existing_alert.ref,
          tool: existing_alert.tool,
          rule_sarif_identifier: existing_alert.rule_sarif_identifier,
          alert_created_at: existing_alert.alert_created_at,
          alert_updated_at: new_alert_updated_at,
          alert_resolved_at: existing_alert.alert_resolved_at,
          alert_severity: existing_alert.alert_severity,
          alert_resolved: true,
          alert_resolution: existing_alert.alert_resolution
        )

        # Prevent the existing record from being found
        CodeScanningPullRequestAlert.stubs(:find_by).returns(nil)

        raised = states("raised").starts_as("no")
        CodeScanningPullRequestAlert \
          .expects(:create!)
          .once
          .with { CodeScanningPullRequestAlert.unstub(:find_by) } # Allow the existing record to be found on the second attempt
          .then(raised.is("yes"))
          .raises(ActiveRecord::RecordNotUnique)
        CodeScanningPullRequestAlert \
          .any_instance
          .expects(:update!)
          .once
          .when(raised.is("yes"))

        CodeScanningPullRequestAlert.upsert(payload)
      end

      context "when dry run" do
        test "does not create record for new alert" do
          now = Time.now
          payload = CodeScanningPullRequestAlert::UpdatePayload.new(
            repository_id: 1,
            alert_number: 2,
            pull_request_id: 3,
            analysis_id: 4,
            ref: "refs/heads/pr",
            tool: "CodeQL",
            rule_sarif_identifier: "woof",
            alert_created_at: now - 10.days,
            alert_updated_at: now,
            alert_resolved_at: now,
            alert_severity: "CRITICAL",
            alert_resolved: true,
            alert_resolution: 1,
            has_dfa: true,
            has_dfa_comments: true,
            has_autofix: true,
            autofix_accepted: true
          )
          assert_nil CodeScanningPullRequestAlert.find_by(
            repository_id: payload.repository_id,
            alert_number: payload.alert_number,
            pull_request_id: payload.pull_request_id
          )

          CodeScanningPullRequestAlert.upsert(payload, dry_run: true)
          assert_nil CodeScanningPullRequestAlert.find_by(
            repository_id: payload.repository_id,
            alert_number: payload.alert_number,
            pull_request_id: payload.pull_request_id
          )

          refute_dogstats_increment "security_overview_analytics.code_scanning_pull_request_alert.unexpected_state"
        end

        test "does not update existing alert" do
          existing_alert = create(:soa_code_scanning_pr_alert)
          updated_at = existing_alert.updated_at
          refute existing_alert.autofix_accepted

          new_alert_updated_at = existing_alert.alert_updated_at + 1.day
          payload = CodeScanningPullRequestAlert::UpdatePayload.new(
            repository_id: existing_alert.repository_id,
            alert_number: existing_alert.alert_number,
            pull_request_id: existing_alert.pull_request_id,
            analysis_id: existing_alert.analysis_id,
            autofix_accepted: true,
            ref: existing_alert.ref,
            tool: existing_alert.tool,
            rule_sarif_identifier: existing_alert.rule_sarif_identifier,
            alert_created_at: existing_alert.alert_created_at,
            alert_updated_at: new_alert_updated_at,
            alert_resolved_at: existing_alert.alert_resolved_at,
            alert_severity: existing_alert.alert_severity,
            alert_resolved: existing_alert.alert_resolved,
            alert_resolution: existing_alert.alert_resolution
          )

          CodeScanningPullRequestAlert.upsert(payload, dry_run: true)
          refute existing_alert.reload.updated_at > updated_at
          refute existing_alert.autofix_accepted

          refute_dogstats_increment "security_overview_analytics.code_scanning_pull_request_alert.unexpected_state"
        end
      end

      context "#validate_and_report_unexpected_state_changes" do
        test "reports existing alert if state deviations found" do
          existing_alert = create(:soa_code_scanning_pr_alert)

          new_alert_updated_at = existing_alert.alert_updated_at + 1.day
          payload = CodeScanningPullRequestAlert::UpdatePayload.new(
            repository_id: existing_alert.repository_id,
            alert_number: existing_alert.alert_number,
            pull_request_id: existing_alert.pull_request_id,
            analysis_id: existing_alert.analysis_id,
            ref: existing_alert.ref,
            tool: existing_alert.tool,
            rule_sarif_identifier: existing_alert.rule_sarif_identifier,
            alert_created_at: existing_alert.alert_created_at,
            alert_updated_at: new_alert_updated_at,
            alert_resolved_at: new_alert_updated_at + 1.day,
            alert_severity: existing_alert.alert_severity,
            alert_resolved: true,
            alert_resolution: existing_alert.alert_resolution
          )

          CodeScanningPullRequestAlert.upsert(payload)

          assert_dogstats_increment 1, "security_overview_analytics.code_scanning_pull_request_alert.unexpected_state", tags: [
            "deviation:alert_resolved",
          ]
        end
      end
    end

    context "#delete_by_repository_ids" do
      test "deletes all revisions on a repository" do
        pr_alert1 = create(:soa_code_scanning_pr_alert)
        pr_alert2 = create(:soa_code_scanning_pr_alert)
        pr_alert3 = create(:soa_code_scanning_pr_alert)
        refute_empty CodeScanningPullRequestAlert.where(repository_id: [pr_alert1.repository_id, pr_alert3.repository_id]).to_a

        CodeScanningPullRequestAlert.delete_by_repository_ids([pr_alert1.repository_id, pr_alert3.repository_id])

        refute_nil CodeScanningPullRequestAlert.find_by(id: pr_alert2.id)
        assert_empty CodeScanningPullRequestAlert.where(repository_id: [pr_alert1.repository_id, pr_alert3.repository_id]).to_a
        assert_dogstats_count_value 2, "security_overview_analytics.code_scanning_pull_request_alerts.deleted"
      end
    end

    context "#fields_with_deviation" do
      test "returns deviations if fields are found different in payload" do
        existing_alert = create(:soa_code_scanning_pr_alert)

        payload = CodeScanningPullRequestAlert::UpdatePayload.new(
          repository_id: existing_alert.repository_id,
          alert_number: existing_alert.alert_number,
          pull_request_id: existing_alert.pull_request_id,
          analysis_id: existing_alert.analysis_id + 1,
          ref: existing_alert.ref,
          tool: existing_alert.tool,
          rule_sarif_identifier: existing_alert.rule_sarif_identifier,
          alert_created_at: existing_alert.alert_created_at,
          alert_updated_at: existing_alert.alert_updated_at,
          alert_resolved_at: existing_alert.alert_resolved_at,
          alert_severity: existing_alert.alert_severity,
          alert_resolved: !existing_alert.alert_resolved,
          alert_resolution: existing_alert.alert_resolution
        )

        assert_equal [:analysis_id, :alert_resolved], existing_alert.fields_with_deviation(payload)
      end
    end

    context "CodeScanningPullRequestAlert::UpdatePayload" do
      context "#serialize" do
        test "returns data matches required payload for data model" do
          now = Time.now
          payload = CodeScanningPullRequestAlert::UpdatePayload.new(
            repository_id: 1,
            alert_number: 2,
            pull_request_id: 3,
            analysis_id: 4,
            ref: "refs/heads/pr",
            tool: "CodeQL",
            rule_sarif_identifier: "woof",
            alert_created_at: now - 10.days,
            alert_updated_at: now,
            alert_resolved_at: now,
            alert_severity: "CRITICAL",
            alert_resolved: true,
            alert_resolution: 1,
            has_dfa: true,
            has_dfa_comments: true,
            has_autofix: true,
            autofix_accepted: true
          )
          assert_nil CodeScanningPullRequestAlert.find_by(
            repository_id: payload.repository_id,
            alert_number: payload.alert_number,
            pull_request_id: payload.pull_request_id
          )

          CodeScanningPullRequestAlert.create!(payload.serialize)
          validate_table_row_with_payload(payload)
        end
      end

      context ".from_pull_request_alert" do
        test "sets payload with active alert" do
          now = Time.now
          alert = ::SecurityProduct::PullRequestAlert.new(
            alert_number: 1,
            analysis_id: 2,
            ref: "refs/heads/pr",
            tool: "CodeQL",
            rule_sarif_identifier: "woof",
            created_at: now - 10.days,
            updated_at: now,
            severity: :CRITICAL,
            fixed: false,
            fixed_at: nil,
            resolution: :NO_RESOLUTION,
            resolved_at: nil,
            has_autofix: true,
            autofix_accepted: true
          )
          alert.has_dfa = true
          alert.has_dfa_comments = true
          payload = CodeScanningPullRequestAlert::UpdatePayload.from_pull_request_alert(
            pull_request: @pull,
            alert:,
            source_event: "woof"
          )

          serialized_payload = payload.serialize
          refute serialized_payload["alert_resolved"]
          assert_nil serialized_payload["alert_resolution"]
        end

        test "sets payload with fixed alert" do
          now = Time.now
          alert = ::SecurityProduct::PullRequestAlert.new(
            alert_number: 1,
            analysis_id: 2,
            ref: "refs/heads/pr",
            tool: "CodeQL",
            rule_sarif_identifier: "woof",
            created_at: now - 10.days,
            updated_at: now,
            severity: :CRITICAL,
            fixed: true,
            fixed_at: now,
            resolution: :NO_RESOLUTION,
            resolved_at: nil,
            has_autofix: true,
            autofix_accepted: true
          )
          alert.has_dfa = true
          alert.has_dfa_comments = true
          payload = CodeScanningPullRequestAlert::UpdatePayload.from_pull_request_alert(
            pull_request: @pull,
            alert:,
            source_event: "woof"
          )

          serialized_payload = payload.serialize
          assert serialized_payload["alert_resolved"]
          assert_nil serialized_payload["alert_resolution"]
        end

        test "sets payload with resolved alert" do
          now = Time.now
          alert = ::SecurityProduct::PullRequestAlert.new(
            alert_number: 1,
            analysis_id: 2,
            ref: "refs/heads/pr",
            tool: "CodeQL",
            rule_sarif_identifier: "woof",
            created_at: now - 10.days,
            updated_at: now,
            severity: :CRITICAL,
            fixed: false,
            fixed_at: nil,
            resolution: :FALSE_POSITIVE,
            resolved_at: nil,
            has_autofix: true,
            autofix_accepted: true
          )
          alert.has_dfa = true
          alert.has_dfa_comments = true
          payload = CodeScanningPullRequestAlert::UpdatePayload.from_pull_request_alert(
            pull_request: @pull,
            alert:,
            source_event: "woof"
          )

          serialized_payload = payload.serialize
          assert serialized_payload["alert_resolved"]
          assert_equal 1, serialized_payload["alert_resolution"]
        end

        test "reports unexpected alert resolved_at" do
          now = Time.now
          alert = ::SecurityProduct::PullRequestAlert.new(
            alert_number: 1,
            analysis_id: 2,
            ref: "refs/heads/pr",
            tool: "CodeQL",
            rule_sarif_identifier: "woof",
            created_at: now - 10.days,
            updated_at: now,
            severity: :CRITICAL,
            fixed: false,
            fixed_at: nil,
            resolution: :WONT_FIX,
            resolved_at: @pull.merged_at + 1.hour,
            has_autofix: false,
            autofix_accepted: false
          )
          alert.has_dfa = false
          alert.has_dfa_comments = false
          payload = CodeScanningPullRequestAlert::UpdatePayload.from_pull_request_alert(
            pull_request: @pull,
            alert:,
            source_event: "woof"
          )

          serialized_payload = payload.serialize
          assert serialized_payload["alert_resolved"]
          refute_nil serialized_payload["alert_resolution"]

          assert_dogstats_increment 1, "security_overview_analytics.code_scanning_pull_request_alert.unexpected_resolved_at", tags: ["source_event:woof"]
        end
      end
    end

    private

    sig { params(payload: CodeScanningPullRequestAlert::UpdatePayload).void }
    def validate_table_row_with_payload(payload)
      row = CodeScanningPullRequestAlert.find_by(
        repository_id: payload.repository_id,
        alert_number: payload.alert_number,
        pull_request_id: payload.pull_request_id
      )
      refute_nil row

      assert_equal Date.id_from_time(payload.alert_created_at), row&.date_id
      assert_equal payload.repository_id, row&.repository_id
      assert_equal payload.alert_number, row&.alert_number
      assert_equal payload.pull_request_id, row&.pull_request_id
      assert_equal payload.analysis_id, row&.analysis_id
      assert_equal payload.ref, row&.ref
      assert_equal payload.tool, row&.tool
      assert_equal payload.rule_sarif_identifier, row&.rule_sarif_identifier
      assert_equal payload.alert_created_at.iso8601(3).to_time.utc, row&.alert_created_at&.utc
      assert_equal payload.alert_updated_at.iso8601(3).to_time.utc, row&.alert_updated_at&.utc
      if payload.alert_resolved_at.nil?
        assert_nil row&.alert_resolved_at&.utc
      else
        assert_equal T.must(payload.alert_resolved_at).iso8601(3).to_time.utc, row&.alert_resolved_at&.utc
      end
      assert_equal payload.alert_severity, row&.alert_severity
      assert_equal payload.alert_resolved, row&.alert_resolved
      assert_equal payload.alert_resolution, row&.alert_resolution
      assert_equal payload.has_dfa, row&.has_dfa
      assert_equal payload.has_dfa_comments, row&.has_dfa_comments
      assert_equal payload.has_autofix, row&.has_autofix
      assert_equal payload.autofix_accepted, row&.autofix_accepted
    end
  end
end
