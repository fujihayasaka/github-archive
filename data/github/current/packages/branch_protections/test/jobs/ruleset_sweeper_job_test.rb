# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RulesetSweeperJobTest < GitHub::TestCase
  include JobTestHelper
  include DogstatsTestHelpers
  include RulesEngine::RefUpdateTestHelper

  fixtures do
    GitHub.flipper[:rules_history].enable
    GitHub.flipper[:ruleset_sweeper_job].enable

    @org_admin = create(:user)
    @org = create(:business_plus_org, admin: @org_admin)
    @repo = create(:repository, owner: @org)
    @ruleset = create(:repository_ruleset, :example_ruleset, source: @repo)

    @suite3 = create_rule_suite(RulesetSweeperJob.expiration_period.ago - 3.days)
    @suite2 = create_rule_suite(RulesetSweeperJob.expiration_period.ago - 2.days)
    @suite1 = create_rule_suite(RulesetSweeperJob.expiration_period.ago - 1.day)
    @suite0 = create_rule_suite(RulesetSweeperJob.expiration_period.ago + 1.day)

    RepositoryRulesetHistory.delete_all
    @history3 = create_ruleset_history(RulesetSweeperJob.expiration_period.ago - 3.days)
    @history2 = create_ruleset_history(RulesetSweeperJob.expiration_period.ago - 2.days)
    @history1 = create_ruleset_history(RulesetSweeperJob.expiration_period.ago - 1.day)
    @history0 = create_ruleset_history(RulesetSweeperJob.expiration_period.ago + 1.day)
  end

  def create_rule_suite(timestamp)
    ref_update = create_branch_update(@repo)
    run = RuleEngine::RuleRun.success(rule_config: @ruleset.rule_configurations.first, ref_update: ref_update)
    suite = RuleEngine::RuleSuite.for_ref_update(ref_update: ref_update, rule_runs: [run], actor: @org_admin)
    suite.save!
    suite.update_columns(created_at: timestamp, updated_at: timestamp)
    suite
  end

  def create_ruleset_history(timestamp)
    @ruleset.name = SecureRandom.uuid
    @ruleset.save!
    history = RepositoryRulesetHistory.last
    history.update_columns(created_at: timestamp, updated_at: timestamp)
    history
  end

  test "enqueues job" do
    RulesetSweeperJob.perform_later
    assert_enqueued_jobs 1, only: RulesetSweeperJob, queue: :ruleset_sweeper
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: RulesetSweeperJob, args: []
  end

  test "respects end date" do
    RulesetSweeperJob.perform_now

    assert_nil RuleEngine::RuleSuite.find_by(id: @suite3.id)
    assert_nil RuleEngine::RuleSuite.find_by(id: @suite2.id)
    assert_nil RuleEngine::RuleSuite.find_by(id: @suite1.id)
    assert_equal @suite0, RuleEngine::RuleSuite.find_by(id: @suite0.id)

    assert_nil RepositoryRulesetHistory.find_by(id: @history3.id)
    assert_nil RepositoryRulesetHistory.find_by(id: @history2.id)
    assert_nil RepositoryRulesetHistory.find_by(id: @history1.id)
    assert_equal @history0, RepositoryRulesetHistory.find_by(id: @history0.id)
  end

  test "respects batch size" do
    # set batch size to 1
    GitHub.flipper[:ruleset_sweeper_batch_size].enable_percentage_of_time(0.01)
    job = RulesetSweeperJob.new
    job.perform

    assert_nil RuleEngine::RuleSuite.find_by(id: @suite3.id)
    assert_equal @suite2, RuleEngine::RuleSuite.find_by(id: @suite2.id)
    assert_equal @suite1, RuleEngine::RuleSuite.find_by(id: @suite1.id)
    assert_equal @suite0, RuleEngine::RuleSuite.find_by(id: @suite0.id)

    assert_nil RepositoryRulesetHistory.find_by(id: @history3.id)
    assert_equal @history2, RepositoryRulesetHistory.find_by(id: @history2.id)
    assert_equal @history1, RepositoryRulesetHistory.find_by(id: @history1.id)
    assert_equal @history0, RepositoryRulesetHistory.find_by(id: @history0.id)

    job.perform
    assert_nil RuleEngine::RuleSuite.find_by(id: @suite3.id)
    assert_nil RuleEngine::RuleSuite.find_by(id: @suite2.id)
    assert_equal @suite1, RuleEngine::RuleSuite.find_by(id: @suite1.id)
    assert_equal @suite0, RuleEngine::RuleSuite.find_by(id: @suite0.id)

    assert_nil RepositoryRulesetHistory.find_by(id: @history3.id)
    assert_nil RepositoryRulesetHistory.find_by(id: @history2.id)
    assert_equal @history1, RepositoryRulesetHistory.find_by(id: @history1.id)
    assert_equal @history0, RepositoryRulesetHistory.find_by(id: @history0.id)
  end

  test "respects expiration days FF" do
    # extend the expiration period by 2 days
    GitHub.flipper[:ruleset_sweeper_expiration_extension].enable_percentage_of_time(0.2)

    job = RulesetSweeperJob.new
    job.perform

    assert_nil RuleEngine::RuleSuite.find_by(id: @suite3.id)
    assert_equal @suite2, RuleEngine::RuleSuite.find_by(id: @suite2.id)
    assert_equal @suite1, RuleEngine::RuleSuite.find_by(id: @suite1.id)
    assert_equal @suite0, RuleEngine::RuleSuite.find_by(id: @suite0.id)

    assert_nil RepositoryRulesetHistory.find_by(id: @history3.id)
    assert_equal @history2, RepositoryRulesetHistory.find_by(id: @history2.id)
    assert_equal @history1, RepositoryRulesetHistory.find_by(id: @history1.id)
    assert_equal @history0, RepositoryRulesetHistory.find_by(id: @history0.id)

    # extend the expiration period by 1 day
    GitHub.flipper[:ruleset_sweeper_expiration_extension].enable_percentage_of_time(0.1)
    job.perform
    assert_nil RuleEngine::RuleSuite.find_by(id: @suite2.id)
    assert_equal @suite1, RuleEngine::RuleSuite.find_by(id: @suite1.id)
    assert_equal @suite0, RuleEngine::RuleSuite.find_by(id: @suite0.id)

    assert_nil RepositoryRulesetHistory.find_by(id: @history2.id)
    assert_equal @history1, RepositoryRulesetHistory.find_by(id: @history1.id)
    assert_equal @history0, RepositoryRulesetHistory.find_by(id: @history0.id)

    GitHub.flipper[:ruleset_sweeper_expiration_extension].enable_percentage_of_time(0)
    job.perform
    assert_nil RuleEngine::RuleSuite.find_by(id: @suite1.id)
    assert_equal @suite0, RuleEngine::RuleSuite.find_by(id: @suite0.id)

    assert_nil RepositoryRulesetHistory.find_by(id: @history1.id)
    assert_equal @history0, RepositoryRulesetHistory.find_by(id: @history0.id)
  end

  test "disabled during replication lag" do
    suite_count = RuleEngine::RuleSuite.all.count
    history_count = RepositoryRulesetHistory.all.count

    job = RulesetSweeperJob.new
    job.stubs(:high_replication_lag?).returns(true)
    assert_equal 0, job.send(:compute_batch_size)

    job.perform

    assert_equal suite_count, RuleEngine::RuleSuite.all.count
    assert_equal history_count, RepositoryRulesetHistory.all.count

    job.stubs(:high_replication_lag?).returns(false)
    job.perform

    assert_equal 1, RuleEngine::RuleSuite.all.count
    assert_equal 1, RepositoryRulesetHistory.all.count
    assert @suite0.reload
    assert @history0.reload
  end
end
