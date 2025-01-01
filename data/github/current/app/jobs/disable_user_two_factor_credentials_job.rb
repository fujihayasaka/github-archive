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
    JobStatus.create(id: DisableUserTwoFactorCredentialsJob.job_id(user.id))
  end

  def self.job_id(user_id)
    "disable-two-factor-credentials_#{user_id}"
  end

  def self.status(user_id)
    JobStatus.find(DisableUserTwoFactorCredentialsJob.job_id(user_id))
  end

  def self.finished?(user_id)
    JobStatus.find(DisableUserTwoFactorCredentialsJob.job_id(user_id)).finished?
  end

  # In order to obtain the ID value of the ORG that is being processed during the loop
  # a `for .. in ` loop i s needed . `each .. do` only allows the use of values inside
  #  of the loop

  # rubocop:disable Style/For
  def perform(user_id, report_org_membership_error: false)
    orgs = orgs(user_id)
    return if orgs.empty?

    if GitHub.flipper[:disable_2fa_job_directly_touch_org].enabled?
      for org in orgs
        with_write { org.remove_any_affiliation(user(user_id), actor: user(user_id)) }
        GitHub.dogstats.increment("jobs.disable_user_two_factor_credentials.user_removed_from_organization")
      end
    else
      for id in org_ids(user_id)
        RemoveUserFromOrganizationJob.perform_now(id, user_id)
      end
    end
    ensure_no_org_membership

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

  def ensure_no_org_membership
    # need a fresh copy of the user model, otherwise the affiliated orgs list is out-of-date
    user = User.find(@user.id)

    # Some org membership is destroyed asynchronously, so we need to double check that no affiliations still
    # exist with orgs requiring 2FA.
    if GitHub.flipper[:disable_user_two_factor_credentials_job_primary_reads].enabled?
      role = :writing
    else
      role = :reading
    end
    ActiveRecord::Base.connected_to(role: role) do
      orgs_with_2fa_requirement = user.affiliated_organizations_with_two_factor_requirement
      if orgs_with_2fa_requirement.any?
        raise UnexpectedOrgMembershipError, "User #{@user.id} still has affiliated organizations with two factor requirement #{orgs_with_2fa_requirement.pluck(:id)}"
      end
    end
  end

  def report_error!(error, org_id, user_id, skip_sentry: false)
    Failbot.report!(error, "gh.org.id": org_id, "gh.user.id": user_id) unless skip_sentry

    GitHub.dogstats.increment("jobs.disable_user_two_factor_credentials.errored", tags: ["error:#{error.class.name}"])
    raise error
  end
end
