# typed: true
# frozen_string_literal: true

require "test_helper"
require "github/turboscan"

class PullRequestAlertSummarizerTest < GitHub::TestCase

  AlertMock = Struct.new(:number, :rule_severity, :security_severity, :location)

  # This arg is not required, but sorbet incorrectly believes that struct requires arg when it doesn't.
  LocationMock = Struct.new(:loc)
  fixtures do
    @user = create(:user)
    @repository = create(:repository)
  end

  def create_summarizer(new_alerts:, fixed_alerts: [], missing_categories: {}, new_categories: {}, diff_truncated: false)
    security_critical_count = 0
    security_high_count = 0
    security_medium_count = 0
    security_low_count = 0
    error_count = 0
    warning_count = 0
    note_count = 0

    new_alerts.each do |alert|
      if alert.security_severity == :CRITICAL
        security_critical_count += 1
      elsif alert.security_severity == :HIGH
        security_high_count += 1
      elsif alert.security_severity == :MEDIUM
        security_medium_count += 1
      elsif alert.security_severity == :LOW
        security_low_count += 1
      elsif alert.rule_severity == :ERROR
        error_count += 1
      elsif alert.rule_severity == :WARNING
        warning_count += 1
      elsif alert.rule_severity == :NOTE
        note_count += 1
      end
    end


    CodeScanning::PullRequestAlertSummarizer.new(
      pull_request_number: 1,
      repository: @repository,
      tool_name: "CodeQL",
      base_ref_name: "refs/heads/main",
      merge_ref_name: "refs/pull/123/merge",
      head_ref_name: "refs/heads/feature",
      merge_commit_oid: "1" * 40,
      head_commit_oid: "2" * 40,
      diff_truncated: diff_truncated,

      missing_categories: missing_categories,
      new_categories: new_categories,

      new_alerts: new_alerts,
      new_count: new_alerts.size,
      fixed_alerts: fixed_alerts,
      fixed_count: fixed_alerts.size,
      security_critical_count: security_critical_count,
      security_high_count: security_high_count,
      security_medium_count: security_medium_count,
      security_low_count: security_low_count,
      error_count: error_count,
      warning_count: warning_count,
      note_count: note_count,
    )
  end

  test "new alerts count as failure and are correctly summarised" do
    summarizer = create_summarizer(new_alerts: [
        AlertMock.new(number: 1, rule_severity: :ERROR),
      ],
    )

    assert_equal "failure", summarizer.conclusion
    assert_equal "1 new alert including 1 error", summarizer.title
    assert_includes summarizer.summary, "New alerts in code changed by this pull request"
    assert_includes summarizer.summary, "* 1 error"
  end

  test "diff with multiple security severities" do
    new_alerts = [
      AlertMock.new(number: 1, security_severity: :CRITICAL, rule_severity: :ERROR),
      AlertMock.new(number: 2, security_severity: :HIGH, rule_severity: :ERROR),
      AlertMock.new(number: 3, security_severity: :MEDIUM, rule_severity: :ERROR),
      AlertMock.new(number: 4, security_severity: :LOW, rule_severity: :ERROR),
      AlertMock.new(number: 5, rule_severity: :ERROR),
      AlertMock.new(number: 6, rule_severity: :ERROR),
      AlertMock.new(number: 7, rule_severity: :WARNING),
      AlertMock.new(number: 8, rule_severity: :NOTE),
    ]
    summarizer = create_summarizer(new_alerts: new_alerts)

    assert_equal "8 new alerts including 1 critical severity security vulnerability", summarizer.title
    assert_includes summarizer.summary, "New alerts in code changed by this pull request"
    assert_includes summarizer.summary, "* 1 critical"
    assert_includes summarizer.summary, "* 1 high"
    assert_includes summarizer.summary, "* 1 medium"
    assert_includes summarizer.summary, "* 1 low"

    assert_includes summarizer.summary, "* 2 errors"
    assert_includes summarizer.summary, "* 1 warning"
    assert_includes summarizer.summary, "* 1 note"
  end

  test "diff with limited new alert list" do
    # The new_alerts list is usually limited to 100 items, even if the actual count is higher.
    alerts = []
    100.times { |i| alerts << AlertMock.new(number: i, rule_severity: :ERROR) }

    summarizer = CodeScanning::PullRequestAlertSummarizer.new(
      pull_request_number: 1,
      repository: @repository,
      tool_name: "CodeQL",

      missing_categories: {},

      new_alerts: alerts,
      new_count: 5000,
      security_critical_count: 0,
      security_high_count: 0,
      security_medium_count: 0,
      security_low_count: 0,
      error_count: 5000,
      warning_count: 0,
      note_count: 0,
    )

    assert_equal "5,000 new alerts including 5,000 errors", summarizer.title
    assert_includes summarizer.summary, "New alerts in code changed by this pull request"
    assert_includes summarizer.summary, " * 5,000 errors"
  end

  test "link to index page" do
    summarizer = create_summarizer(new_alerts: [])
    query = Search::Query.stringify([[:pr, summarizer.pull_request_number], [:tool, summarizer.tool_name], [:is, :open]])
    path = UrlHelpers.repository_code_scanning_results_path(@repository.owner, @repository, query: query)

    assert_includes summarizer.summary, "[View all branch alerts](#{path})"
  end

  test "check run title" do
    # MG: Rewrite this as a loop

    summarizer = create_summarizer(new_alerts: [AlertMock.new(number: 1, rule_severity: :ERROR)])
    assert_equal "1 new alert including 1 error", summarizer.title

    summarizer = create_summarizer(new_alerts: [
      AlertMock.new(number: 1, rule_severity: :ERROR),
      AlertMock.new(number: 2, security_severity: :LOW, rule_severity: :ERROR)
    ])
    assert_equal "2 new alerts including 1 low severity security vulnerability", summarizer.title

    summarizer = create_summarizer(new_alerts: [
      AlertMock.new(number: 1, rule_severity: :ERROR),
      AlertMock.new(number: 2, security_severity: :LOW, rule_severity: :ERROR),
      AlertMock.new(number: 3, security_severity: :MEDIUM, rule_severity: :ERROR)
    ])
    assert_equal "3 new alerts including 1 medium severity security vulnerability", summarizer.title

    summarizer = create_summarizer(new_alerts: [
      AlertMock.new(number: 1, rule_severity: :ERROR),
      AlertMock.new(number: 2, security_severity: :LOW, rule_severity: :ERROR),
      AlertMock.new(number: 3, security_severity: :MEDIUM, rule_severity: :ERROR),
      AlertMock.new(number: 4, security_severity: :HIGH, rule_severity: :ERROR)
    ])
    assert_equal "4 new alerts including 1 high severity security vulnerability", summarizer.title

    summarizer = create_summarizer(new_alerts: [
      AlertMock.new(number: 1, rule_severity: :ERROR),
      AlertMock.new(number: 2, security_severity: :LOW, rule_severity: :ERROR),
      AlertMock.new(number: 3, security_severity: :MEDIUM, rule_severity: :ERROR),
      AlertMock.new(number: 4, security_severity: :HIGH, rule_severity: :ERROR),
      AlertMock.new(number: 5, security_severity: :CRITICAL, rule_severity: :ERROR)
    ])
    assert_equal "5 new alerts including 1 critical severity security vulnerability", summarizer.title


    summarizer = create_summarizer(new_alerts: [
      AlertMock.new(number: 1, security_severity: :CRITICAL, rule_severity: :ERROR),
      AlertMock.new(number: 2, security_severity: :CRITICAL, rule_severity: :ERROR)
    ])
    assert_equal "2 new alerts including 2 critical severity security vulnerabilities", summarizer.title
  end

  test "with missing categories" do
    @repository.store_code_scanning_action_in_progress("refs/heads/feature", "2" * 40, "python🦠", "123")

    summarizer = create_summarizer(
      new_alerts: [],
      missing_categories: {
        "python🦠" => Turboscan::Proto::MissingCategorySummary.new(delivery_origin: Turboscan::Proto::DeliveryOrigin::DELIVERY_ORIGIN_YML, workflow_path: ".github/workflows/\xF0\x9F\xA6\xA0codeql.yml".b),
        "javascript" => Turboscan::Proto::MissingCategorySummary.new(delivery_origin: Turboscan::Proto::DeliveryOrigin::DELIVERY_ORIGIN_YML, workflow_path: ".github/workflows/\xF0\x9F\xA6\xA0codeql.yml".b),
        "" => Turboscan::Proto::MissingCategorySummary.new(delivery_origin: Turboscan::Proto::DeliveryOrigin::DELIVERY_ORIGIN_API, workflow_path: ""),
      },
    )

    assert_equal "neutral", summarizer.conclusion
    assert_equal "3 configurations not found", summarizer.title
    assert_includes summarizer.summary, "**Warning**: Code scanning cannot determine the alerts introduced by this pull request, because 3 configurations present on `refs/heads/main` were not found:\n\n"
    assert_includes summarizer.summary, "### Actions workflow (`🦠codeql.yml`)\n\n* :question:&nbsp;&nbsp;`javascript`\n* :hourglass:&nbsp;&nbsp;`python🦠`\n"
    assert_includes summarizer.summary, "### API upload\n\n* :question:&nbsp;&nbsp;&lt;default&gt;\n"
  end

  test "with many missing categories" do
    @repository.store_code_scanning_action_in_progress("refs/heads/feature", "2" * 40, "python", "123")

    missing_categories = {}
    (1..500).each do |i|
      missing_categories["𠮷" * 900 + i.to_s] = Turboscan::Proto::MissingCategorySummary.new(delivery_origin: Turboscan::Proto::DeliveryOrigin::DELIVERY_ORIGIN_YML, workflow_path: ".github/workflows/codeql.yml")
    end

    summarizer = create_summarizer(
      new_alerts: [],
      missing_categories: missing_categories,
    )

    run = build(:check_run)

    assert_nothing_raised do
      # This will throw an exception if the summary is too long
      run.update_for_code_scanning_diff!(summarizer)
    end
  end

  test "with new categories" do
    alerts = []
    10.times { |i| alerts << AlertMock.new(number: i, security_severity: :CRITICAL) }

    summarizer = create_summarizer(
      new_alerts: alerts,
      missing_categories: {},
      new_categories: {
        "foo" => Turboscan::Proto::NewCategorySummary.new(alert_count: 13),
        "bar" => Turboscan::Proto::NewCategorySummary.new(alert_count: 0),
      },
    )

    assert_equal "failure", summarizer.conclusion
    assert_equal "10 new alerts including 10 critical severity security vulnerabilities", summarizer.title

    assert summarizer.onboarding_experience_comment?

    comment = summarizer.onboarding_experience_comment
    assert_includes comment, "This pull request sets up GitHub code scanning for this repository."
    assert_includes comment, "Once the scans have completed and the checks have passed, the analysis results for this pull request branch will appear on"
    assert_includes comment, "Once you merge this pull request, the 'Security' tab will show more code scanning analysis results"
    refute_includes comment, "CodeQL"
  end

  test "summary includes security alerts irrespective of the configured security severity on the repo" do
    CodeScanningRepositoryConfig.new(@repository).set_code_scanning_security_severity_choice(choice: Configurable::CodeScanningSeverities::SECURITY_SEVERITY_HIGH_OR_HIGHER, actor: @user)

    summarizer = create_summarizer(new_alerts: [
      AlertMock.new(number: 1, security_severity: :MEDIUM),
    ],
  )

    assert_includes summarizer.summary, "Security Alerts:\n * 1 medium\n"
  end

  test "summary has no mention of new or fixed alerts if there aren't any" do
    summarizer = create_summarizer(new_alerts: [], fixed_alerts: [])
    refute_includes summarizer.summary.downcase, "new alerts"
    refute_includes summarizer.summary.downcase, "fixed alerts"
  end

  test "summary has no mention of fixed alerts if there are only new alerts" do
    summarizer = create_summarizer(new_alerts: [
      AlertMock.new(number: 1, security_severity: :MEDIUM)
    ], fixed_alerts: [])
    assert_includes summarizer.summary.downcase, "new alerts"
    refute_includes summarizer.summary.downcase, "fixed alerts"
  end

  context "alert severity choice" do
    test "check_run fails with an error" do
      summarizer = create_summarizer(new_alerts: [AlertMock.new(number: 1, rule_severity: :ERROR, location: LocationMock.new)])
      assert_equal summarizer.conclusion, "failure"
    end

    test "check_run succeeds with an error when severity choice is none only" do
      CodeScanningRepositoryConfig.new(@repository).set_code_scanning_severity_choice(choice: Configurable::CodeScanningSeverities::SEVERITY_CHOICE_NONE, actor: @user)
      summarizer = create_summarizer(new_alerts: [AlertMock.new(number: 1, rule_severity: :ERROR, location: LocationMock.new)])
      assert_equal summarizer.conclusion, "success"
    end

    test "check_run succeeds with a warning when severity choice is errors only" do
      CodeScanningRepositoryConfig.new(@repository).set_code_scanning_severity_choice(choice: Configurable::CodeScanningSeverities::SEVERITY_CHOICE_ERRORS, actor: @user)
      summarizer = create_summarizer(new_alerts: [AlertMock.new(number: 1, rule_severity: :WARNING, location: LocationMock.new)])
      assert_equal summarizer.conclusion, "success"
    end

    test "check_run fails with a warning when severity choice is errors and warnings" do
      CodeScanningRepositoryConfig.new(@repository).set_code_scanning_severity_choice(choice: Configurable::CodeScanningSeverities::SEVERITY_CHOICE_ERRORS_AND_WARNINGS, actor: @user)
      summarizer = create_summarizer(new_alerts: [AlertMock.new(number: 1, rule_severity: :WARNING, location: LocationMock.new)])
      assert_equal summarizer.conclusion, "failure"
    end

    test "check_run succeeds with a note when severity choice is errors and warnings" do
      CodeScanningRepositoryConfig.new(@repository).set_code_scanning_severity_choice(choice: Configurable::CodeScanningSeverities::SEVERITY_CHOICE_ERRORS_AND_WARNINGS, actor: @user)
      summarizer = create_summarizer(new_alerts: [AlertMock.new(number: 1, rule_severity: :NOTE, location: LocationMock.new)])
      assert_equal summarizer.conclusion, "success"
    end

    test "check_run fails with a note when severity choice is all" do
      CodeScanningRepositoryConfig.new(@repository).set_code_scanning_severity_choice(choice: Configurable::CodeScanningSeverities::SEVERITY_CHOICE_ALL, actor: @user)
      summarizer = create_summarizer(new_alerts: [AlertMock.new(number: 1, rule_severity: :NOTE, location: LocationMock.new)])
      assert_equal summarizer.conclusion, "failure"
    end

    test "check_run fails with a warning when severity choice is all" do
      CodeScanningRepositoryConfig.new(@repository).set_code_scanning_severity_choice(choice: Configurable::CodeScanningSeverities::SEVERITY_CHOICE_ALL, actor: @user)
      summarizer = create_summarizer(new_alerts: [AlertMock.new(number: 1, rule_severity: :WARNING, location: LocationMock.new)])
      assert_equal summarizer.conclusion, "failure"
    end
  end

  context "alert security severity choice" do
    test "security severity choice none works" do
      CodeScanningRepositoryConfig.new(@repository).set_code_scanning_security_severity_choice(choice: Configurable::CodeScanningSeverities::SECURITY_SEVERITY_NONE, actor: @user)

      summarizer = create_summarizer(new_alerts: [AlertMock.new(number: 1, security_severity: :CRITICAL, location: LocationMock.new)])
      assert_equal summarizer.conclusion, "success"
    end

    test "security severity choice critical works" do
      CodeScanningRepositoryConfig.new(@repository).set_code_scanning_security_severity_choice(choice: Configurable::CodeScanningSeverities::SECURITY_SEVERITY_CRITICAL, actor: @user)

      summarizer = create_summarizer(new_alerts: [AlertMock.new(number: 1, security_severity: :CRITICAL, location: LocationMock.new)])
      assert_equal summarizer.conclusion, "failure"

      summarizer = create_summarizer(new_alerts: [AlertMock.new(number: 1, security_severity: :HIGH, location: LocationMock.new)])
      assert_equal summarizer.conclusion, "success"
    end

    test "security severity choice high and higher works" do
      CodeScanningRepositoryConfig.new(@repository).set_code_scanning_security_severity_choice(choice: Configurable::CodeScanningSeverities::SECURITY_SEVERITY_HIGH_OR_HIGHER, actor: @user)

      summarizer = create_summarizer(new_alerts: [AlertMock.new(number: 1, security_severity: :CRITICAL, location: LocationMock.new)])
      assert_equal summarizer.conclusion, "failure"

      summarizer = create_summarizer(new_alerts: [AlertMock.new(number: 1, security_severity: :HIGH, location: LocationMock.new)])
      assert_equal summarizer.conclusion, "failure"

      summarizer = create_summarizer(new_alerts: [AlertMock.new(number: 1, security_severity: :MEDIUM, location: LocationMock.new)])
      assert_equal summarizer.conclusion, "success"
    end

    test "security severity choice medium or higher works" do
      CodeScanningRepositoryConfig.new(@repository).set_code_scanning_security_severity_choice(choice: Configurable::CodeScanningSeverities::SECURITY_SEVERITY_MEDIUM_OR_HIGHER, actor: @user)

      summarizer = create_summarizer(new_alerts: [AlertMock.new(number: 1, security_severity: :CRITICAL, location: LocationMock.new)])
      assert_equal summarizer.conclusion, "failure"

      summarizer = create_summarizer(new_alerts: [AlertMock.new(number: 1, security_severity: :HIGH, location: LocationMock.new)])
      assert_equal summarizer.conclusion, "failure"

      summarizer = create_summarizer(new_alerts: [AlertMock.new(number: 1, security_severity: :MEDIUM, location: LocationMock.new)])
      assert_equal summarizer.conclusion, "failure"

      summarizer = create_summarizer(new_alerts: [AlertMock.new(number: 1, security_severity: :LOW, location: LocationMock.new)])
      assert_equal summarizer.conclusion, "success"
    end

    test "security severity choice all works" do
      CodeScanningRepositoryConfig.new(@repository).set_code_scanning_security_severity_choice(choice: Configurable::CodeScanningSeverities::SECURITY_SEVERITY_ALL, actor: @user)

      summarizer = create_summarizer(new_alerts: [AlertMock.new(number: 1, security_severity: :CRITICAL, location: LocationMock.new)])
      assert_equal summarizer.conclusion, "failure"

      summarizer = create_summarizer(new_alerts: [AlertMock.new(number: 1, security_severity: :HIGH, location: LocationMock.new)])
      assert_equal summarizer.conclusion, "failure"

      assert_equal summarizer.conclusion, "failure"

      summarizer = create_summarizer(new_alerts: [AlertMock.new(number: 1, security_severity: :LOW, location: LocationMock.new)])
      assert_equal summarizer.conclusion, "failure"
    end

    test "pr check is successful if there are no alerts" do
      CodeScanningRepositoryConfig.new(@repository).set_code_scanning_security_severity_choice(choice: Configurable::CodeScanningSeverities::SECURITY_SEVERITY_ALL, actor: @user)
      summarizer = create_summarizer(new_alerts: [])

      assert_equal summarizer.conclusion, "success"
      assert_equal summarizer.title, "No new alerts in code changed by this pull request"
      refute summarizer.summary.include?("No new alerts")
    end

    test "summary includes a note if diff was truncated and there are new alerts" do
      CodeScanningRepositoryConfig.new(@repository).set_code_scanning_security_severity_choice(choice: Configurable::CodeScanningSeverities::SECURITY_SEVERITY_ALL, actor: @user)
      summarizer = create_summarizer(new_alerts: [AlertMock.new(number: 1, security_severity: :CRITICAL, location: LocationMock.new)], diff_truncated: true)

      assert_equal summarizer.conclusion, "failure"
      assert_includes summarizer.summary, "detected because the code changes were too large"
    end
  end

  context "forked repo" do
    test "should not post onboarding comment" do
      forker = create :user
      forked_repo = create(:fork_repository, forker: forker, fork_repo: @repository)

      summarizer = CodeScanning::PullRequestAlertSummarizer.new(
        pull_request_number: 1,
        repository: forked_repo,
        tool_name: "CodeQL",

        new_alerts: [],
        new_count: 10,
        new_categories: {
          "foo" => Turboscan::Proto::NewCategorySummary.new(alert_count: 13),
          "bar" => Turboscan::Proto::NewCategorySummary.new(alert_count: 0),
        },
        missing_categories: {},
        security_critical_count: 10,
        security_high_count: 0,
        security_medium_count: 0,
        security_low_count: 0,
        error_count: 0,
        warning_count: 0,
        note_count: 0,
      )

      refute summarizer.onboarding_experience_comment?
    end
  end
end
