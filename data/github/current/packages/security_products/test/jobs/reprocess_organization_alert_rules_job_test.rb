# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ReprocessOrganizationAlertRulesJobTest < GitHub::TestCase
  include JobTestHelper
  include DependabotAlertsEnterpriseEnablementHelper
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    @business = create(:business)
    @business.mark_advanced_security_as_purchased_for_entity(actor: User.ghost)
    @org = create(:organization, business: @business)
    @custom_rule = create(:vulnerability_alert_rule, target: @org)
  end

  context "#perform" do
    test "raises an ArgumentError when given an invalid action" do
      assert_raises(ArgumentError) do
        ReprocessOrganizationAlertRulesJob.perform_now(
          organization_id: @org.id,
          rule_id: @custom_rule.id,
          action: :invalid_input_lol
        )
      end
    end

    test "enqueues a ReprocessAlertRulesJob with created_rule_id with the :created action" do
      repo = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, :meets_auto_dismiss_conditions, repository: repo)

      args = { repository_id: repo.id, created_rule_id: @custom_rule.id }
      assert_enqueued_with(job: ReprocessAlertRulesJob, args: [args]) do
        ReprocessOrganizationAlertRulesJob.perform_now(
          organization_id: @org.id,
          rule_id: @custom_rule.id,
          action: :created
        )
      end
    end

    test "enqueues a ReprocessAlertRulesJob with deleted_rule_id with the :deleted action" do
      repo = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, :meets_auto_dismiss_conditions, repository: repo)

      args = { repository_id: repo.id, deleted_rule_id: @custom_rule.id }
      assert_enqueued_with(job: ReprocessAlertRulesJob, args: [args]) do
        ReprocessOrganizationAlertRulesJob.perform_now(
          organization_id: @org.id,
          rule_id: @custom_rule.id,
          action: :deleted
        )
      end
    end

    test "enqueues a ReprocessAlertRulesJob with disabled_rule_id with the :disabled action" do
      repo = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, :meets_auto_dismiss_conditions, repository: repo)

      args = { repository_id: repo.id, disabled_rule_ids: [@custom_rule.id] }
      assert_enqueued_with(job: ReprocessAlertRulesJob, args: [args]) do
        ReprocessOrganizationAlertRulesJob.perform_now(
          organization_id: @org.id,
          rule_id: @custom_rule.id,
          action: :disabled
        )
      end
    end

    test "enqueues a ReprocessAlertRulesJob with edited_rule_id with the :edited action" do
      repo = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, :meets_auto_dismiss_conditions, repository: repo)

      args = { repository_id: repo.id, edited_rule_id: @custom_rule.id }
      assert_enqueued_with(job: ReprocessAlertRulesJob, args: [args]) do
        ReprocessOrganizationAlertRulesJob.perform_now(
          organization_id: @org.id,
          rule_id: @custom_rule.id,
          action: :edited
        )
      end
    end

    test "enqueues a ReprocessAlertRulesJob with enabled_rule_ids with the :enabled action" do
      repo = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, :meets_auto_dismiss_conditions, repository: repo)

      args = { repository_id: repo.id, enabled_rule_ids: @custom_rule.id }
      assert_enqueued_with(job: ReprocessAlertRulesJob, args: [args]) do
        ReprocessOrganizationAlertRulesJob.perform_now(
          organization_id: @org.id,
          rule_id: @custom_rule.id,
          action: :enabled
        )
      end
    end

    test "enqueues a ReprocessAlertRulesJob with the default rule with the :enabled action" do
      repo = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, :meets_auto_dismiss_conditions, repository: repo)

      args = { repository_id: repo.id, enabled_rule_ids: VulnerabilityAlertRule.default_auto_dismissal_rule_id }
      assert_enqueued_with(job: ReprocessAlertRulesJob, args: [args]) do
        ReprocessOrganizationAlertRulesJob.perform_now(
          organization_id: @org.id,
          rule_id: VulnerabilityAlertRule.default_auto_dismissal_rule_id,
          rule_target_type: "global",
          action: :enabled
        )
      end
    end

    test "enqueues one ReprocessAlertRulesJob per found repository" do
      repo = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      another_repo = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      [repo, another_repo].each do |repository|
        create(:repository_vulnerability_alert, :meets_auto_dismiss_conditions, repository:)
      end

      ReprocessOrganizationAlertRulesJob.perform_now(
        organization_id: @org.id,
        rule_id: @custom_rule.id,
        action: :enabled
      )
      assert_enqueued_with job: ReprocessAlertRulesJob, args: [{ repository_id: repo.id, enabled_rule_ids: @custom_rule.id }]
      assert_enqueued_with job: ReprocessAlertRulesJob, args: [{ repository_id: another_repo.id, enabled_rule_ids: @custom_rule.id }]
    end

    test "filters found repositories by rule criteria" do
      # This repository has an alert that doesn't match our custom rule so we don't expect it to be enqueued:
      repo_to_ignore = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, repository: repo_to_ignore)

      # This repository has an alert that matches our custom rule so we expect it to be enqueued:
      repo_to_find = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, :meets_auto_dismiss_conditions, repository: repo_to_find)

      args = { repository_id: repo_to_find.id, enabled_rule_ids: @custom_rule.id }
      assert_enqueued_jobs(1) do
        assert_enqueued_with(job: ReprocessAlertRulesJob, args: [args]) do
          ReprocessOrganizationAlertRulesJob.perform_now(
            organization_id: @org.id,
            rule_id: @custom_rule.id,
            action: :enabled
          )
        end
      end
    end

    test "WaitForReplication is included by default" do
      # Disable this flag so that the all features mode doesn't break this test:
      disable_feature_flag(:active_job_default_to_write_connection)

      WaitForReplication.any_instance.stubs(:wait!).raises(WaitForReplication::DataUnavailable.new(
        store_name: :"notify",
        wait_required: 2.0,
        max_wait: 2.0
      ))

      assert_enqueued_jobs(1, only: ReprocessOrganizationAlertRulesJob) do
        ReprocessOrganizationAlertRulesJob.perform_now(
          organization_id: @org.id,
          rule_id: @custom_rule.id,
          action: :enabled
        )
      end
    end
  end

  context "#find_repository_ids_with_alerts" do
    test "does not include archived repositories" do
      archived_repo = create(:archived_repository, owner: @org)
      assert_predicate archived_repo, :archived?

      assert_empty create_dummy_job.find_repository_ids_with_alerts
    end

    test "does not include deleted repositories" do
      deleted_repo = create(:deleted_repository, owner: @org)
      assert_predicate deleted_repo, :deleted?

      assert_empty create_dummy_job.find_repository_ids_with_alerts
    end

    test "does not include repositories with vulnerability alerts disabled" do
      repo = create(:repository, :vulnerability_alerts_disabled, owner: @org)
      refute_predicate repo, :vulnerability_alerts_enabled?

      assert_empty create_dummy_job.find_repository_ids_with_alerts
    end

    test "does not include repositories with 0 vulnerability alerts" do
      repo = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      assert_predicate repo, :vulnerability_alerts_enabled?
      assert_equal 0, repo.repository_vulnerability_alerts.count

      assert_empty create_dummy_job.find_repository_ids_with_alerts
    end

    test "includes public repositories" do
      repo = create(:public_repository, :vulnerability_alerts_enabled, owner: @org)
      assert_predicate repo, :vulnerability_alerts_enabled?

      # Create an RVA so that we'll return this repository:
      create(:repository_vulnerability_alert, repository: repo)
      assert_equal 1, repo.repository_vulnerability_alerts.count

      assert_same_elements [repo.id], create_dummy_job.find_repository_ids_with_alerts
    end

    test "does not include private repositories with GHAS disabled" do
      # Disble flags which enable GHAS features on non-GHAS repos, so this test works in all-features mode:
      disable_feature_flag(:dependabot_alerts_freebies)
      disable_feature_flag(:security_center_private_beta)

      repo = create(:private_repository, :vulnerability_alerts_enabled, owner: @org)
      assert_predicate repo, :vulnerability_alerts_enabled?
      refute_predicate repo, :advanced_security_enabled?

      # Create an RVA so that we'll return this repository:
      create(:repository_vulnerability_alert, repository: repo)
      assert_equal 1, repo.repository_vulnerability_alerts.count

      assert_empty create_dummy_job.find_repository_ids_with_alerts
    end

    test "includes private repositories with GHAS enabled" do
      repo = create(:private_repository, :vulnerability_alerts_enabled, owner: @org)
      repo.enable_advanced_security!(actor: User.ghost)
      assert_predicate repo, :vulnerability_alerts_enabled?
      assert_predicate repo, :advanced_security_enabled?

      # Create an RVA so that we'll return this repository:
      create(:repository_vulnerability_alert, repository: repo)
      assert_equal 1, repo.repository_vulnerability_alerts.count

      assert_same_elements [repo.id], create_dummy_job.find_repository_ids_with_alerts
    end

    test "returns repository IDs which contain alerts" do
      repo_with_alerts = create(:public_repository, :vulnerability_alerts_enabled, owner: @org)
      assert_predicate repo_with_alerts, :vulnerability_alerts_enabled?
      create(:repository_vulnerability_alert, repository: repo_with_alerts)
      assert_equal 1, repo_with_alerts.repository_vulnerability_alerts.count

      repo_without_alerts = create(:public_repository, :vulnerability_alerts_enabled, owner: @org)
      assert_predicate repo_without_alerts, :vulnerability_alerts_enabled?
      assert_equal 0, repo_without_alerts.repository_vulnerability_alerts.count

      assert_same_elements [repo_with_alerts.id], create_dummy_job.find_repository_ids_with_alerts
    end
  end

  context "#filter_repositories_by_rule" do
    test "returns repos containing alerts by CWE specified" do
      rule = create(:vulnerability_alert_rule, conditions: { cwe: %w(CWE-400) })
      matching_vulnerability = create(:published_vulnerability, :auto_dismissable) # auto_dismissable uses CWE-400

      # This repository will have an alert w/ runtime scope, which the rule WON'T match:
      repo_without_alert = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, repository: repo_without_alert)

      # This repository will have an alert w/ development scope, which the rule WILL match:
      repo_with_alert = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, vulnerability: matching_vulnerability, repository: repo_with_alert)

      assert_same_elements [repo_with_alert.id],
        create_dummy_job(rule: rule).filter_repositories_by_rule([repo_without_alert.id, repo_with_alert.id])
    end

    test "returns repos containing alerts by scope specified" do
      # Our rule will target development scoped dependencies:
      rule = create(:vulnerability_alert_rule, conditions: { scope: %w(development) })

      # This repository will have an alert w/ runtime scope, which the rule WON'T match:
      repo_without_alert = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, dependency_scope: "runtime", repository: repo_without_alert)

      # This repository will have an alert w/ development scope, which the rule WILL match:
      repo_with_alert = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, dependency_scope: "development", repository: repo_with_alert)

      assert_same_elements [repo_with_alert.id],
        create_dummy_job(rule: rule).filter_repositories_by_rule([repo_without_alert.id, repo_with_alert.id])
    end

    test "returns repos containing alerts by ecosystem" do
      rule = create(:vulnerability_alert_rule, conditions: { ecosystem: %w(npm) })

      repo_without_alert = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, ecosystem: "RubyGems", repository: repo_without_alert)

      repo_with_alert = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, ecosystem: "npm", repository: repo_with_alert)

      assert_same_elements [repo_with_alert.id],
        create_dummy_job(rule: rule).filter_repositories_by_rule([repo_without_alert.id, repo_with_alert.id])
    end

    test "returns repos containing alerts by package" do
      rule = create(:vulnerability_alert_rule, conditions: { package: %w(leftpad) })

      repo_without_alert = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, affects: "rightpad", repository: repo_without_alert)

      repo_with_alert = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, affects: "leftpad", repository: repo_with_alert)

      assert_same_elements [repo_with_alert.id],
        create_dummy_job(rule: rule).filter_repositories_by_rule([repo_without_alert.id, repo_with_alert.id])
    end

    test "returns repos containing alerts by severity" do
      rule = create(:vulnerability_alert_rule, conditions: { severity: %w(low) })

      repo_without_alert = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, severity: :critical, repository: repo_without_alert)

      repo_with_alert = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, severity: :low, repository: repo_with_alert)

      assert_same_elements [repo_with_alert.id],
        create_dummy_job(rule: rule).filter_repositories_by_rule([repo_without_alert.id, repo_with_alert.id])
    end

    test "returns repos containing alerts by CVE ID" do
      vulnerability = create(:vulnerability, :with_cve)
      rule = create(:vulnerability_alert_rule, conditions: { cve_id: [vulnerability.cve_id] })

      repo_without_alert = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, severity: :critical, repository: repo_without_alert)

      repo_with_alert = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, severity: :low, repository: repo_with_alert, vulnerability:)

      assert_same_elements [repo_with_alert.id],
        create_dummy_job(rule: rule).filter_repositories_by_rule([repo_without_alert.id, repo_with_alert.id])
    end

    test "returns repos containing alerts by GHSA ID" do
      vulnerability = create(:vulnerability)
      rule = create(:vulnerability_alert_rule, conditions: { ghsa_id: [vulnerability.ghsa_id] })

      repo_without_alert = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, severity: :critical, repository: repo_without_alert)

      repo_with_alert = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, severity: :low, repository: repo_with_alert, vulnerability:)

      assert_same_elements [repo_with_alert.id],
        create_dummy_job(rule: rule).filter_repositories_by_rule([repo_without_alert.id, repo_with_alert.id])
    end

    test "returns repos containing alerts by EPSS value" do
      advisory_with_epss = create(:vulnerability, :with_cve)
      create(:cve_epss, vulnerability: advisory_with_epss, percentage: 0.81)
      rule = create(:vulnerability_alert_rule, conditions: { epss: ["percentage>0.8"] })

      repo_without_alert = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, severity: :critical, repository: repo_without_alert)

      repo_with_alert = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, severity: :low, repository: repo_with_alert, vulnerability: advisory_with_epss)

      assert_same_elements [repo_with_alert.id],
        create_dummy_job(rule: rule).filter_repositories_by_rule([repo_without_alert.id, repo_with_alert.id])
    end

    test "emits timing stats to Datadog" do
      assert_empty create_dummy_job(rule: @custom_rule).filter_repositories_by_rule([])
      assert_dogstats_distribution 1, "reprocess_organization_alert_rules_job.filter_repositories_by_rule.time"
    end

    test "raises an ArgumentError when a rule contains an unknown condition" do
      rule_with_unexpected_condition = build(:vulnerability_alert_rule,
        conditions: {
          unknown: ["known-unknown"]
        }
      )
      # In order to test invalid conditions, we need to skip the validator on rules:
      assert rule_with_unexpected_condition.save(validate: false)

      assert_raises ArgumentError do
        create_dummy_job(rule: rule_with_unexpected_condition).filter_repositories_by_rule([1])
      end
    end

    test "logs before/after count stats" do
      rule = create(:vulnerability_alert_rule, conditions: { severity: %w(low) })

      repo_without_alert = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, severity: :critical, repository: repo_without_alert)

      repo_with_alert = create(:repository, :vulnerability_alerts_enabled, owner: @org)
      create(:repository_vulnerability_alert, severity: :low, repository: repo_with_alert)

      expected_log_output = {
        "Body": "Filter repo IDs results",
        "code.namespace": "ReprocessOrganizationAlertRulesJob",
        "code.function": "filter_repositories_by_rule",
        "gh.org.id": @org.id,
        "gh.security_alerts.filter_repositories_by_rule.before_count": 2,
        "gh.security_alerts.filter_repositories_by_rule.after_count": 1,
      }
      assert_logged(**expected_log_output) do
        assert_same_elements [repo_with_alert.id],
          create_dummy_job(rule: rule).filter_repositories_by_rule([repo_without_alert.id, repo_with_alert.id])
      end
    end
  end

  # Helper to create instances of the job class to test with. This is necessry because params would normally be passed
  # in using perform_later, but in order to test individual methods on the job class we'll need to manually set the
  # instance variables which usually happens in the perform method.
  #
  def create_dummy_job(overrides = {})
    job = ReprocessOrganizationAlertRulesJob.new

    args = { organization_id: @org.id, rule: @custom_rule, action: :edited }.merge(overrides)
    args.each do |k, v|
      job.instance_variable_set "@#{k}".to_sym, v
    end

    job
  end
end unless GitHub.enterprise?
