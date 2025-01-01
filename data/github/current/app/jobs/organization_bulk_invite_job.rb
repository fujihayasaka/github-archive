# typed: true
# frozen_string_literal: true

class OrganizationBulkInviteJob < ApplicationJob
  queue_as :organization_bulk_invite

  # Public: Perform the job.
  #
  # actor - User performing the bulk invitation.
  # organization - Organization to which members are being invited.
  # members - Enumerable of String representing either a user login or
  #   an email to invite.
  # previous_invitation_ids - Optional Enumerable of Integer for the IDs of
  #   the OrganizationInvitations representing the previous invitations if
  #   we are retrying invitations.
  #   If previous_invitation_ids is provided, it must be a direct ordered
  #   mapping for the provided members. Defaults to [].
  #
  # Returns Hash.
  def perform(actor, organization, members, previous_invitation_ids = [])
    results = T.let({
      errors: [],
      successes: [],
      }, T.untyped)

    members.each_with_index do |member, index|
      if previous_invitation_ids.any? && members.size == previous_invitation_ids.size && previous_invitation_ids[index]
        provided_value = previous_invitation_ids[index]
        previous_invitation = OrganizationInvitation.includes(:teams).find(provided_value)
        provided_role = previous_invitation&.role
        provided_teams = previous_invitation&.teams
        provided_source = previous_invitation&.invitation_source
      end
      role = provided_role || :direct_member
      teams = provided_teams || []
      source = provided_source&.to_sym == :unknown ? :member : provided_source
      results = invite_member_with_reporting(actor, organization, member, role, teams, results, source)
    end

    instrument_results(actor, organization, results)

    if results[:errors].any?
      failures_for_mailer = results[:errors].map do |error|
        # Ensure we just set the invitee login as the member field for the email
        member = error[:member].is_a?(::User) ? error[:member].login : error[:member]
        {
          member: member,
          class: error[:class],
          message: error[:message],
        }
      end
      AccountMailer.org_invitation_failed(
        actor,
        organization,
        failures_for_mailer.to_json
      ).deliver_later
    end

    results
  end

  private

  def invite_member_with_reporting(actor, organization, member, role, teams, results, source, rate_limit = true)
    invitee_or_email = if User.valid_email?(member)
      member
    else
      User.find_by login: member
    end

    begin
      invite_member(actor, organization, invitee_or_email, role, teams, source, rate_limit)
      results[:successes] << invitee_or_email
    rescue OrganizationInvitation::NoAvailableSeatsError, OrganizationInvitation::TradeControlsError,
           OrganizationInvitation::AlreadyAcceptedError, OrganizationInvitation::InvalidError,
           ActiveRecord::RecordInvalid => ex
      results[:errors] << {
        member: invitee_or_email,
        class: ex.class.to_s,
        message: ex.message,
      }

      log_inactionable_error(actor, organization.id, member, ex)
    end

    results
  end

  def invite_member(actor, organization, invitee_or_email, role, teams, source, rate_limit)
    source ||= :member

    if User.valid_email?(invitee_or_email)
      email = invitee_or_email
    else
      invitee = invitee_or_email
    end

    if rate_limit && organization.invitation_rate_limit_exceeded?
      GitHub.dogstats.increment("rate_limited", tags: ["job:organization_bulk_invite_job"])
      GitHub.logger.info(
        "info.message" => organization.invitation_rate_limit_error_message,
        "gh.actor.id" => actor.id,
        "gh.organization.id" => organization.id,
        "gh.job.active_job_id" => job_id
      )
      return
    end

    with_write do
      organization.invite(invitee, email: email, inviter: actor, teams: teams, role: role, invitation_source: source)
    end
  end

  def instrument_results(actor, organization, results)
    email_successes = results[:successes].reject { |member| member.respond_to?(:id) }
    successful_ids = results[:successes].select { |member| member.respond_to?(:id) }
      .map(&:id)

    email_errors = results[:errors].reject { |member| member[:member].respond_to?(:id) }.
      map { |m| m[:member] }
    error_ids = results[:errors].select { |member| member[:member].respond_to?(:id) }.
      map { |m| m[:member].id }

    GlobalInstrumenter.instrument(
      "organization.bulk.invite",
      actor: actor,
      organization: organization,
      successful_user_invites: successful_ids,
      successful_email_invites: email_successes,
      failed_user_invites: error_ids,
      failed_email_invites: email_errors,
    )
  end

  # Log generic errors when failed invites are not created
  def log_inactionable_error(actor, organization_id, member, error)
    return unless [OrganizationInvitation::AlreadyAcceptedError, OrganizationInvitation::InvalidError, ActiveRecord::RecordInvalid].include?(error.class)

    GitHub.logger.error({
      exception: error,
      "code.namespace": self.class.name,
      "code.function": "invite_member_with_reporting",
      "enduser.id": actor.id,
      "gh.thisuser": member,
      "gh.org.id": organization_id,
    })
  end
end
