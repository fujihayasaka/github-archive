# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Subscribes a User in MailChimp and
# starts the welcome series workflow.
class MailchimpSubscribeJob < ApplicationJob
  queue_as :mailchimp

  MailchimpTryLaterError = Class.new(StandardError)
  retry_on MailchimpTryLaterError

  WORKFLOW_OPTIONS = {
    beginner: {
      id: GitHub::Mailchimp::BEGINNER_ONBOARDING_SERIES_WORKFLOW_ID,
      email_id: GitHub::Mailchimp::BEGINNER_ONBOARDING_SERIES_WORKFLOW_EMAIL_ID,
    },
    intermediate: {
      id: GitHub::Mailchimp::INTERMEDIATE_ONBOARDING_SERIES_WORKFLOW_ID,
      email_id: GitHub::Mailchimp::INTERMEDIATE_ONBOARDING_SERIES_WORKFLOW_EMAIL_ID,
    },
    generic: {
      id: GitHub::Mailchimp::GENERIC_ONBOARDING_SERIES_WORKFLOW_ID,
      email_id: GitHub::Mailchimp::GENERIC_ONBOARDING_SERIES_WORKFLOW_EMAIL_ID,
    },
  }

  def perform(email_id, options = {})
    @email_id = email_id
    @email    = UserEmail.find_by(id: email_id)
    @user     = @email.try(:user)
    @options  = options.with_indifferent_access

    Failbot.push(
      job: self.class.name,
      user: @user.try(:login),
      email_id: @email_id,
    )

    GitHub.dogstats.increment "mailchimp", tags: ["job:subscribe_email"]
    return unless @email && @user
    return unless @email.should_be_subscribed_in_mailchimp?

    @mailchimp = GitHub::Mailchimp.new(@email)

    with_mailchimp_retries do
      @mailchimp.subscribe
      begin_welcome_series if should_receive_welcome_series?
    end
  end

  # Public: Start the welcome series workflow for
  # the user if they should receive it.
  def begin_welcome_series
    @mailchimp.start_workflow(
      workflow_id:       workflow_options.fetch(:id),
      workflow_email_id: workflow_options.fetch(:email_id),
    )

    # Record the completion of an onboarding event for the user.
    with_write { Onboarding.for(@user).enrolled_in_welcome_series! }
  rescue GitHub::Mailchimp::Error => boom
    ignored_errors = [
      "The subscriber has already been triggered for this email",
      "already sent this email to the subscriber",
    ]

    return if boom.status_code == 400 &&
      ignored_errors.any? { |e| boom.detail.include?(e) }
    raise
  end

  # Public: When MailChimp API calls fail due to 5xx server errors,
  # retry the call up to 25 times. Otherwise, raise an exception
  # and fail the job.
  def with_mailchimp_retries(&block)
    yield
  rescue GitHub::Mailchimp::Error => boom
    if GitHub::Mailchimp::ServerErrorStatuses.include?(boom.status_code)
      GitHub.dogstats.increment "mailchimp", tags: ["job:subscribe_email", "type:retry"]

      raise MailchimpTryLaterError
    else
      raise
    end
  end

  private

  # Private: Should the user receive the welcome email series?
  # Returns a Boolean.
  def should_receive_welcome_series?
    recent_signup? && !already_received_welcome_series?
  end

  # Private: Whether or not a user already received the welcome series.
  # Returns a Boolean.
  def already_received_welcome_series?
    onboarding = Onboarding.for(@user)
    onboarding.welcomed_via_email? || onboarding.enrolled_in_welcome_series?
  end

  # Private: Did the user sign up recently?
  # Returns a Boolean.
  def recent_signup?
    @user.created_at > 30.days.ago
  end

  # Private: Determine which workflow a user should be enrolled in
  # based on the workflow series combo experiment.
  #
  # Returns the MailChimp workflow options as a Hash.
  def workflow_options
    @workflow_options ||= if @user.beginner_level_experience?
      WORKFLOW_OPTIONS[:beginner]
    elsif @user.intermediate_level_experience?
      WORKFLOW_OPTIONS[:intermediate]
    else
      WORKFLOW_OPTIONS[:generic]
    end
  end
end
