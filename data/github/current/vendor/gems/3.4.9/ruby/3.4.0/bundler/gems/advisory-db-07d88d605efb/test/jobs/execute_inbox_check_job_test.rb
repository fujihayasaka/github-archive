# frozen_string_literal: true

require "test_helper"

class ExecuteInboxCheckJobTest < ActiveJob::TestCase
  test "records check info when check passes" do
    advisory_review = create(:advisory_review)

    CheckSuiteRunner.expects(:update_check_status).with({
      check_class: SuccessCheck,
      review: advisory_review,
      status: "running",
    }).once

    CheckSuiteRunner.expects(:update_check_status).with({
      check_class: SuccessCheck,
      review: advisory_review,
      status: "passed",
      message: "PASS! - This test check always passes",
    }).once

    ExecuteInboxCheckJob.new.perform(
      check_class_name: "SuccessCheck",
      review: advisory_review,
    )
  end

  test "records check info when check fails" do
    advisory_review = create(:advisory_review)
    CheckSuiteRunner.expects(:update_check_status).with({
      check_class: FailCheck,
      review: advisory_review,
      status: "running",
    }).once

    CheckSuiteRunner.expects(:update_check_status).with({
      check_class: FailCheck,
      review: advisory_review,
      status: "failed",
      message: "FAIL! - This test check reliably fails",
    }).once

    ExecuteInboxCheckJob.new.perform(
      check_class_name: "FailCheck",
      review: advisory_review,
    )
  end

  test "records check info when check warns" do
    advisory_review = create(:advisory_review)
    CheckSuiteRunner.expects(:update_check_status).with({
      check_class: WarnCheck,
      review: advisory_review,
      status: "running",
    }).once

    CheckSuiteRunner.expects(:update_check_status).with({
      check_class: WarnCheck,
      review: advisory_review,
      status: "warning",
      message: "WARN! - This test check reliably warns",
    }).once

    ExecuteInboxCheckJob.new.perform(
      check_class_name: "WarnCheck",
      review: advisory_review,
    )
  end

  test "records check info when check raises exception" do
    advisory_review = create(:advisory_review)

    CheckSuiteRunner.expects(:update_check_status).with({
      check_class: RaisesExceptionCheck,
      review: advisory_review,
      status: "running",
    }).once

    CheckSuiteRunner.expects(:update_check_status).with({
      check_class: RaisesExceptionCheck,
      review: advisory_review,
      status: "failed",
      message: "Check Raised Exception - undefined method `[]' for nil",
    }).once

    ExecuteInboxCheckJob.new.perform(
      check_class_name: "RaisesExceptionCheck",
      review: advisory_review,
    )
  end
end

# A test check that always succeeds
class SuccessCheck
  def self.should_run?(_)
    true
  end

  def self.execute_check(review:)
    CheckResult.new(status: "passed", title: "PASS!", summary: "This test check always passes")
  end
end

# A test check that always fails
class FailCheck
  def self.should_run?(_)
    true
  end

  def self.execute_check(review:)
    CheckResult.new(status: "failed", title: "FAIL!", summary: "This test check reliably fails")
  end
end

# A test check that always warns
class WarnCheck
  def self.should_run?(_)
    true
  end

  def self.execute_check(review:)
    CheckResult.new(status: "warning", title: "WARN!", summary: "This test check reliably warns")
  end
end

class RaisesExceptionCheck
  def self.should_run?(_)
    true
  end

  def self.execute_check(review:)
    # some illegal code that raises an error...
    [][0][:gonna_fail]
  end
end
