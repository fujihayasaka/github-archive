# typed: true
# frozen_string_literal: true

class TeamsMailer < ApplicationMailer
  include ApplicationHelper

  self.mailer_name = "mailers/teams"

  # Notifies people when they're added to a team
  def team_added(user, team, adder)
    # no notifications are sent for EMU users
    return if user.is_enterprise_managed?

    @org = team.organization
    @team = team
    @url = "#{GitHub.url}/orgs/#{@org}/teams/#{team.slug}"
    @signature = notification_signature(@url)

    subject = if adder
      "\"#{adder.safe_profile_name}\" added you to the \"#{@org.safe_profile_name}\" team \"#{team.name}\""
    else
      "You've been added to the \"#{@org.safe_profile_name}\" team \"#{team.name}\""
    end

    mail(
      from: github_noreply(team.organization),
      to: user_org_approved_email(user, @org),
      subject: subject,
      categories: "org,org-team-add-member",
    )
  end

  def removed_from_team(user, team_name, org, legacy_owner:, team_destroyed: false)
    # no notifications are sent for EMU users
    return if user.is_enterprise_managed?

    @org = org
    @team_destroyed = team_destroyed
    @team_name = team_name
    @send_owners_team_email = legacy_owner && @org.adminable_by?(user)
    @signature = notification_signature(@url)

    subject = if @team_destroyed
      if @send_owners_team_email
        "Important: We've made changes to the Owners team on \"#{@org.safe_profile_name}\""
      else
        "The \"#{@org.safe_profile_name}\" team \"#{@team_name}\" has been deleted"
      end
    else
      "You've been removed from the \"#{@org.safe_profile_name}\" team \"#{@team_name}\""
    end

    mail(
      from: github_noreply(@org),
      to: user_org_approved_email(user, @org),
      subject: subject,
      categories: "org,org-team-remove-member",
    )
  end

  def team_membership_request(requester:, team:)
    @requester     = requester
    @team          = team
    @org_name      = @team.organization.safe_profile_name
    @approvals_url = team_members_url(@team.organization, @team)
    recipients  = team_authoritative_emails(@team)

    mail(
      bcc: recipients,
      subject: "\"#{@requester.display_login}\" would like to join \"#{@org_name}\"'s \"#{@team.name}\" team",
      from: github_noreply(@team.organization),
    )
  end

  def team_relationship_request(requester:, parent_team:, child_team:, initiated_by_parent:)
    @requester          = requester
    @parent_team        = parent_team
    @child_team         = child_team
    @target_team        = initiated_by_parent ? child_team : parent_team
    @org_name           = "\"#{@child_team.organization.safe_profile_name}\""
    @approvals_url      = if initiated_by_parent
      team_teams_url(@parent_team.organization, @child_team)
    else
      team_teams_url(@child_team.organization, @parent_team)
    end

    recipients = team_authoritative_emails(@target_team)

    subject = if initiated_by_parent
      "\"#{@requester.display_login}\" wants to make \"#{@child_team.name}\" team a child team of #{@org_name}'s \"#{@parent_team.name}\" team."
    else
      "\"#{@requester.display_login}\" wants to make \"#{@parent_team.name}\" team the parent of #{@org_name}'s \"#{@child_team.name}\" team."
    end

    mail(
      bcc:     recipients,
      subject: subject,
      from:    github_noreply(@parent_team.organization),
    )
  end

  private

  # Private: An organization's admins' email addresses that are on a specific team.
  # Excluding suspended admins. Use this to set
  # From, To, CC, and Reply-To headers.
  #
  # team - A team.
  #
  # Returns an Array of String email addresses with
  # the admins' full names (if available).
  def org_admins_in_team_emails(team)
    org = team.organization
    admin_mails = org.admins.map do |admin|
      next if admin.suspended?
      next unless team.member? admin
      user_org_approved_email(admin, org)
    end
    # Remove nil entries, as both 'next' and 'user_email' may return nil.
    admin_mails.compact
  end

  # Email addresses for a team's maintainers. Excluding suspended maintainers.
  # Use this to set From, To, CC, and Reply-To headers.
  #
  # team - A team.
  #
  # Returns the email string with the maintainers' full names if available.
  def team_maintainer_emails(team)
    maintainer_emails = team.maintainers.map do |maintainer|
      next if maintainer.suspended?
      user_org_approved_email(maintainer, team.organization)
    end

    # Remove nil entries, as both 'next' and 'user_email' may return nil.
    maintainer_emails.compact
  end

  def team_authoritative_emails(team)
    if team_maintainer_emails(team).present?
      team_maintainer_emails(team)
    elsif org_admins_in_team_emails(team).present?
      org_admins_in_team_emails(team)
    else
      admin_emails(team.organization)
    end
  end

  # A user's name and email address in mail header format. Use this to set From,
  # To, CC, and Reply-To headers.
  #
  # user - A user or organization.
  # email - (Optional) Email address in String form. Will default to the
  #   user's email if none is passed.
  # allow_private - (Optional) Whether or not private email addresses will be
  #   returned. Defaults to true, but should be set to false if the email
  #   could be shown to someone other than the passed user (like for a
  #   From or Reply-To header).
  #
  # Returns the email string with the user's full name if available.
  # Returns nil if emails cannot be sent for that user/org (for example because of domain restrictions).
  def user_org_approved_email(user, org)
    settings = GitHub.newsies.settings(user).value
    approved_email = settings.email(org)&.address if org.user_can_receive_email_notifications?(user)

    user_email(user, approved_email) if approved_email
  end

  # Public: An organization's admins' email addresses.
  # Excluding suspended admins and custom excluded. Use this to set
  # From, To, CC, and Reply-To headers.
  #
  # org - An organization to get admins from.
  # except - a list of admins we don't want to include.
  #
  # Returns an Array of String email addresses with
  # the admins' full names (if available).
  # For example an admin email is unavailable if the org has domain restrictions.
  def admin_emails(org)
    admin_mails = org.admins.map do |admin|
      next if admin.suspended?
      user_org_approved_email(admin, org)
    end

    # Remove nil entries, as both 'next' and 'user_email' may return nil.
    admin_mails.compact
  end
end
