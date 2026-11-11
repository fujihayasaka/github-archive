# typed: true
# frozen_string_literal: true

class BusinessTeamsMailer < ApplicationMailer
  include ApplicationHelper

  self.mailer_name = "mailers/business_teams"

  layout "layouts/primer_layout"

  def added_to_team(user, business, team)
    # No notifications are sent for EMU users
    return if user.is_enterprise_managed?

    @user = user
    @business = business
    @team = team
    @members_count = team.member_ids.size
    @org_count = team.organization_ids.size
    @repo_count = team.direct_or_inherited_repo_ids.size
    @team_url = team.permalink

    subject = %Q[You've been added to the "#{team.name}" team on the "#{@business.safe_profile_name}" enterprise]

    premail(
      from: github,
      to: user_email(@user),
      subject: subject
    )
  end

  def removed_from_team(user, business, team_name, team_destroyed: false)
    # No notifications are sent for EMU users
    return if user.is_enterprise_managed?

    @user = user
    @business = business
    @team_name = team_name
    @team_destroyed = team_destroyed

    subject = if @team_destroyed
      %Q[The "#{@business.safe_profile_name}" enterprise team "#{@team_name}" has been deleted]
    else
      %Q[You've been removed from the "#{@business.safe_profile_name}" enterprise team "#{@team_name}"]
    end

    premail(
      from: github,
      to: user_email(@user),
      subject: subject
    )
  end

  def added_to_organization(user, business, team_name, org_name, actor: nil, member_count: nil)
    # No notifications are sent for EMU users
    return if user.is_enterprise_managed?

    @user = user
    @business = business
    @team_name = team_name
    @org_name = org_name
    @actor = actor
    @member_count = member_count
    @org_url = "#{GitHub.url}/#{org_name}"

    premail(
      from: github,
      to: user_email(@user),
      subject: %Q[The "#{@team_name}" team has been added to the "#{@org_name}" organization]
    )
  end

  def added_to_organizations(user, business, team, org_count, actor: nil, member_count: nil)
    # No notifications are sent for EMU users
    return if user.is_enterprise_managed?

    @user = user
    @business = business
    @team_name = team.name
    @org_count = org_count
    @actor = actor
    @member_count = member_count
    @team_url = "#{GitHub.url}/enterprises/#{business.slug}/teams/#{team.slug}"

    premail(
      from: github,
      to: user_email(@user),
      subject: %Q[The "#{@team_name}" team has been added to #{@org_count} organizations]
    )
  end

  def removed_from_organization(user, business, team_name, org_name)
    # No notifications are sent for EMU users
    return if user.is_enterprise_managed?

    @user = user
    @business = business
    @team_name = team_name
    @org_name = org_name
    @org_url = "#{GitHub.url}/#{org_name}"

    premail(
      from: github,
      to: user_email(@user),
      subject: %Q[The "#{@team_name}" team has been removed from the "#{@org_name}" organization]
    )
  end

  def removed_from_organizations(user, business, team, org_count)
    # No notifications are sent for EMU users
    return if user.is_enterprise_managed?

    @user = user
    @business = business
    @team_name = team.name
    @org_count = org_count
    @team_url = "#{GitHub.url}/enterprises/#{business.slug}/teams/#{team.slug}"

    premail(
      from: github,
      to: user_email(@user),
      subject: %Q[The "#{@team_name}" team has been removed from #{@org_count} organizations]
    )
  end
end
