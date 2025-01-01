# typed: true
# frozen_string_literal: true

require "test_helper"

class MarketingFormsSubmissionTest < GitHub::TestCase
  fixtures do
    @valid_raw_data = { email: "hello@world.com", cDLProgramName: "example-name-here", marketingConsent: "optInExplicit" }
  end

  test "validating email" do
    raw_data = { cDLProgramName: "example-name-here", marketingConsent: "optInExplicit" }
    submission = MarketingForms::Submission.new(form_name: "test", raw_data: raw_data)

    refute submission.valid?
    assert submission.errors[:email].include?("Valid email key is missing. Valid keys are: email, email_address, emailAddress")

    raw_data[:email] = "hello@world.com"
    submission = MarketingForms::Submission.new(form_name: "test", raw_data: raw_data)

    assert submission.valid?
    raw_data.delete(:email)

    raw_data[:email_address] = "hello@world.com"
    submission = MarketingForms::Submission.new(form_name: "test", raw_data: raw_data)

    assert submission.valid?
    raw_data.delete(:email_address)

    raw_data[:emailAddress] = "hello@world.com"
    submission = MarketingForms::Submission.new(form_name: "test", raw_data: raw_data)

    assert submission.valid?
  end

  test "validating cDLProgramName" do
    raw_data = { email: "hello@world.com", marketingConsent: "optInExplicit" }
    submission = MarketingForms::Submission.new(form_name: "test", raw_data: raw_data)

    refute submission.valid?
  end

  test "validating marketingConsent" do
    raw_data = T.let({ email: "hello@world.com", cDLProgramName: "example-name-here", marketingConsent: "invalid" }, T::Hash[Symbol, T.untyped])
    submission = MarketingForms::Submission.new(form_name: "test", raw_data: raw_data)

    refute submission.valid?

    raw_data[:marketingConsent] = nil
    submission = MarketingForms::Submission.new(form_name: "test", raw_data: raw_data)

    refute submission.valid?

    raw_data[:marketingConsent] = "optInExplicit"
    submission = MarketingForms::Submission.new(form_name: "test", raw_data: raw_data)

    assert submission.valid?

    raw_data.delete(:marketingConsent)
    submission = MarketingForms::Submission.new(form_name: "test", raw_data: raw_data)

    assert submission.valid?
  end

  test "enqueueing a submission" do
    raw_data = { email: "hello@world.com", cDLProgramName: "example-name-here", marketingConsent: "optInExplicit" }
    submission = MarketingForms::Submission.new(form_name: "test", raw_data: raw_data)

    assert_enqueued_with(job: MarketingFormsSubmissionJob, args: [{ form_name: "test", raw_data: raw_data }]) do
      submission.enqueue
    end
  end

  test "enqueueing an invalid submission" do
    raw_data = { cDLProgramName: "example-name-here", marketingConsent: "optInExplicit" }
    submission = MarketingForms::Submission.new(form_name: "test", raw_data: raw_data)

    assert_no_enqueued_jobs do
      refute submission.enqueue
    end
  end

  test "raising an error when trying to enqueue! and invalid submission" do
    raw_data = { cDLProgramName: "example-name-here", marketingConsent: "optInExplicit" }
    submission = MarketingForms::Submission.new(form_name: "test", raw_data: raw_data)

    assert_raises ActiveModel::ValidationError do
      submission.enqueue!
    end
  end

  test "enqueuing using the class method" do
    raw_data = { email: "hello@world.com", cDLProgramName: "example-name-here", marketingConsent: "optInExplicit" }

    assert_enqueued_with(job: MarketingFormsSubmissionJob, args: [{ form_name: "test", raw_data: raw_data }]) do
      submission = MarketingForms::Submission.enqueue!(form_name: "test", raw_data: raw_data)
      assert submission.is_a?(MarketingForms::Submission)
    end
  end

  test "raising a validation error when enqueuing with the class method" do
    raw_data = { cDLProgramName: "example-name-here", marketingConsent: "optInExplicit" }

    assert_raises ActiveModel::ValidationError do
      MarketingForms::Submission.enqueue!(form_name: "test", raw_data: raw_data)
    end
  end
end
