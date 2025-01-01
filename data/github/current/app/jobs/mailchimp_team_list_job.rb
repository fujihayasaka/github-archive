# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

class MailchimpTeamListJob < ApplicationJob
  queue_as :mailchimp

  include MailchimpTeamListHelper

  class MailchimpServerError < StandardError; end

  MAX_SERVER_ERROR_RETRIES = 25
  IGNORED_ERRORS = [
    "The subscriber has already been triggered for this email",
    "already sent this email to the subscriber",
  ]
  LIST_ID = GitHub::Mailchimp::GITHUB_TEAM_LIST

  retry_on(MailchimpServerError, wait: :polynomially_longer, attempts: MAX_SERVER_ERROR_RETRIES) do |_job, _error|
    GitHub.dogstats.increment "mailchimp", tags: ["job:team_list.retry"]
  end

  def perform(user:, org:)
    return false unless user.present? && org.present? && subscribe_to_team_list?(user: user, org: org)

    email = UserEmail.find_by_email(user.email)
    return false unless email.present?

    mailchimp = GitHub::Mailchimp.new(email)

    # Subscribe uses upsert under the hood so this will update or create a new subscription for the user
    subscribe(user: user, org: org, mailchimp: mailchimp)

    if start_team_admin_onboarding?(user: user, org: org)
      start_team_admin_onboarding_campaign(user: user, org: org, mailchimp: mailchimp)
    end

    true
  rescue GitHub::Mailchimp::Error => boom
    return false if boom.status_code == 400 && IGNORED_ERRORS.any? { |e| boom.detail.include?(e) }
    raise MailchimpServerError if GitHub::Mailchimp::ServerErrorStatuses.include?(boom.status_code)
    raise
  end

  def subscribe(user:, org:, mailchimp:)
    mailchimp.subscribe(
      list_id: LIST_ID,
      merge_fields: GitHub::Mailchimp.team_merge_fields(**user_merge_fields(user, org))
    )

    GitHub.dogstats.increment "mailchimp", tags: ["job:team_list.subscribe"]
  rescue GitHub::Mailchimp::Error => boom
    raise
  end

  def start_team_admin_onboarding_campaign(user:, org:, mailchimp:)
    mailchimp.ensure_subscriber_exists(LIST_ID) do
      mailchimp.start_workflow(
        workflow_id:       GitHub::Mailchimp::TEAM_ADMIN_ONBOARDING_WORKFLOW_ID,
        workflow_email_id: GitHub::Mailchimp::TEAM_ADMIN_ONBOARDING_EMAIL_ID,
      )
    end

    # Record the completion of an onboarding event for the user.
    with_write { Onboarding.for(user).enrolled_in_team_admin_onboarding_series! }

    GitHub.dogstats.increment "mailchimp", tags: ["job:team_list.start_team_admin_onboarding_campaign"]
  end
end
