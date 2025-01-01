# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class DisableUserTwoFactorCredentialsJob < ApplicationJob
  # In order to destroy a users two_factor_credential, they must first be
  # removed from all organizations where 2fa is a requirement
  # otherwise the destroy fails
  # Since we need to remove a user from multiple orgs, and cannot track a large
  # number of job statuses, this job executes the RemoveUserFromOrganizationJob
  # synchronously, and then performs the destruction of the users
  # Two factor credential in an after_perform hook

  queue_as :remove_user_from_org

  attr_reader :user_id

  MAX_ATTEMPTS = 10

  UnexpectedOrgMembershipError = Class.new(RuntimeError)

  retry_on_dirty_exit

  # Only a single unique instance of the job can be concurrently running
  # per user being removed
  locked_by timeout: 1.hour, key: -> (job) { "disable_user_two_factor_credentials::#{job.arguments[0]}" }

  after_perform do |_job|
    ActiveRecord::Base.connected_to(role: :writing) do
      @user.two_factor_credential.destroy
    end
  end

  before_enqueue do |job|
    # Create a JobStatus for the job being enqueued.
    user = user(job.arguments.first)
    GitHub::Authentication::JobStatus.create(id: DisableUserTwoFactorCredentialsJob.job_id(user.id))
  end

  def self.prefix
    "disable-two-factor-credentials"
  end

  def self.job_id(user_id)
    "#{prefix}_#{user_id}"
  end

  def self.status(user_id)
    GitHub::Authentication::JobStatus.find(DisableUserTwoFactorCredentialsJob.job_id(user_id))
  end

  def self.finished?(user_id)
    GitHub::Authentication::JobStatus.find(DisableUserTwoFactorCredentialsJob.job_id(user_id)).finished?
  end

  # In order to obtain the ID value of the ORG that is being processed during the loop
  # a `for .. in ` loop i s needed . `each .. do` only allows the use of values inside
  #  of the loop

  # rubocop:disable Style/For
  def perform(user_id, report_org_membership_error: false)
    orgs = orgs(user_id)
    return if orgs.empty?

    for id in org_ids(user_id)
      next if @user.may_retain_affiliation_without_2fa?(Organization.find(id))

      RemoveUserFromOrganizationJob.perform_now(id, user_id)
    end

  rescue DisableUserTwoFactorCredentialsJob::UnexpectedOrgMembershipError => error
    report_error!(error, id, user_id, skip_sentry: !report_org_membership_error)
  rescue => error # rubocop:todo Lint/GenericRescue
    report_error!(error, id, user_id)
  end
  # rubocop:enable Style/For

  def user(id)
    @user ||= User.find(id)
  end

  def org_ids(user_id)
    orgs(user_id).pluck(:id)
  end

  def orgs(user_id)
    @orgs ||= user(user_id).affiliated_organizations_with_two_factor_requirement
  end

  private

  def report_error!(error, org_id, user_id, skip_sentry: false)
    Failbot.report!(error, "gh.org.id": org_id, "gh.user.id": user_id) unless skip_sentry

    GitHub.dogstats.increment("jobs.disable_user_two_factor_credentials.errored", tags: ["error:#{error.class.name}"])
    raise error
  end
end
