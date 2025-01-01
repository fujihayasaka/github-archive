# typed: true
# frozen_string_literal: true

class RepositoryBulkInviteJob < ApplicationJob
  queue_as :repository_bulk_invite

  # Public: Perform the job.
  #
  # actor - User performing the bulk invitation.
  # repository_invites - Array of failed repository invites.
  #
  # Returns Hash.
  def perform(actor, repository_invite_ids, organization_id = nil)
    results = {
      errors: [],
      successes: [],
    }

    # construct a hash by repository id
    # repo_hashes = {
    #   repo_id => { :users => [list of users/emails], results => { :errors => [], :successes => [] }}},
    #   repo_id => { :users => [list of users/emails], results => { :errors => [], :successes => [] }}}
    # }
    repo_hashes = {}

    RepositoryInvitation.where(id: repository_invite_ids).includes(
      :invitee, :repository
    ).each do |invitation|
      with_write do
        next if !repo_rate_limit_ok(invitation, actor, organization_id)

        invitation.cancel!(actor: actor, force: true)
        repo_hash = repo_hashes[invitation.repository_id] ||
          { repository: invitation.repository, users: [], results: { errors: [], successes: [] } }

        if invitation.invitee.present?
          # Check for user login invite duplicates
          if !repo_hash[:users].include?(invitation.invitee.id)
            result = RepositoryInvitation.invite_to_repo(invitation.invitee, actor, invitation.repository, action: invitation.permissions)
            repo_hash = add_to_repo_hash(
              repo_hash: repo_hash,
              actor: actor,
              invitation: invitation,
              result: result,
              repository: invitation.repository,
              organization_id: organization_id
            )
          end
        elsif invitation.email.present?
          # Check for email invite duplicates
          if !repo_hash[:users].include?(invitation.email) && User.valid_email?(invitation.email)
            result = RepositoryInvitation.invite_to_repo_by_email(invitation.email, actor, invitation.repository, action: invitation.permissions)
            repo_hash = add_to_repo_hash(
              repo_hash: repo_hash,
              actor: actor,
              invitation: invitation,
              result: result,
              repository: invitation.repository,
              organization_id: organization_id
            )
          end
        end

        repo_hashes[invitation.repository_id] = repo_hash
      end
    end

    # send analytics per repo id
    repo_hashes.each do |_repo_id, repo_hash|
      repository = repo_hash[:repository]
      results[:successes].concat((repo_hash[:results])[:successes])
      results[:errors].concat((repo_hash[:results])[:errors])

      if organization_id.present?
        org = Organization.find_by(id: organization_id)
      end
      instrument_results(actor, repository, repo_hash[:results], org)
    end

    results
  end

  private

  # Add users and emails to repo hash for analytics
  def add_to_repo_hash(repo_hash:, actor:, invitation:, result:, repository:, organization_id:)
    user_id_or_email = invitation.invitee_id || invitation.email
    repo_hash[:users] << user_id_or_email
    if result[:success].present?
      (repo_hash[:results])[:successes] << user_id_or_email
    else
      (repo_hash[:results])[:errors] << user_id_or_email
      log_inactionable_invite(actor, invitation, __method__.to_s, result[:errors].full_messages.to_sentence, repository.id, organization_id)
    end

    repo_hash
  end

  # Send data per repo id for analytics
  def instrument_results(actor, repository, results, organization)
    email_successes = results[:successes].select { |member| member.is_a?(String) }
    successful_ids = results[:successes].reject { |member| member.is_a?(String) }

    email_errors = results[:errors].select { |member| member.is_a?(String) }
    error_ids = results[:errors].reject { |member| member.is_a?(String) }

    GlobalInstrumenter.instrument(
      "repository.bulk.invite",
      actor: actor,
      repository: repository,
      successful_user_invites: successful_ids,
      successful_email_invites: email_successes,
      failed_user_invites: error_ids,
      failed_email_invites: email_errors,
      organization: organization
    )
  end

  # Checks if the rate limit has been exceeded for the repository. If so, logs
  # the error and returns false - otherwise, returns true
  def repo_rate_limit_ok(invitation, actor, organization_id = nil)
    return true unless !invitation.rate_limit_not_exceeded?

    GitHub.dogstats.increment("rate_limited", tags: ["job:repository_bulk_invite_job"])
    log_inactionable_invite(actor, invitation, __method__.to_s, "Rate limit exceeded for this repository", invitation.repository_id, organization_id)

    false
  end

  # Logs an invitation that was unable to be processed, and why.
  # RepositoryInvitation method calls used fail "silently" and propagate errors
  # upwards using a hash, therefore we use Logger.log instead of Logger.log_exception,
  # which would also need to be executed within a rescue block.
  def log_inactionable_invite(actor, invitation, method, reason, repository_id, organization_id = nil)
    GitHub.logger.info(
      reason,
      "code.namespace" => self.class.name,
      "code.function" => method,
      "gh.actor.id" => actor.id,
      "gh.invitee.id" => invitation.invitee_id,
      "gh.repo.id" => repository_id,
      "gh.org.id" => organization_id,
    )
  end

end
