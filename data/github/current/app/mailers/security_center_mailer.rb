# typed: strict
# frozen_string_literal: true

class SecurityCenterMailer < ApplicationMailer

  self.mailer_name = "mailers/security_center"

  layout "layouts/primer_layout"

  sig { params(user: User, owner: T.any(Business, User), csv_url: String, feature: String, query_string: String, end_date: Date, row_type: String, file_expiration: Time).void }
  def csv_export_ready(user:, owner:, csv_url:, feature:, query_string:, end_date:, row_type:, file_expiration:)
    @user = T.let(user, T.nilable(User))
    @owner = T.let(owner, T.nilable(T.any(Business, User)))
    @csv_url = T.let("#{GitHub.url}#{csv_url}", T.nilable(String))
    @feature = T.let(feature, T.nilable(String))
    @query_string = T.let(query_string, T.nilable(String))
    @end_date = T.let(end_date, T.nilable(Date))
    @row_type = T.let(row_type, T.nilable(String))
    @file_expiration_date = T.let(file_expiration.utc.strftime("%B %-d, %Y at %H:%M UTC"), T.nilable(String))

    @title = T.let("Your #{feature} CSV is ready", T.nilable(String))
    @footer_text = T.let("You are receiving this email because you requested your #{feature} data.", T.nilable(String))

    premail(
      from: github_noreply,
      to: [GitHub.newsies.email(user, owner)],
      bcc: [],
      subject: "[GitHub] Your #{feature} CSV is ready",
    )
  end

  sig { params(user: User, owner: T.any(Business, User), redirect_url: String, feature: String, query_string: String, end_date: Date).void }
  def csv_export_error(user:, owner:, redirect_url:, feature:, query_string:, end_date:)
    @user = T.let(user, T.nilable(User))
    @owner = T.let(owner, T.nilable(T.any(Business, User)))
    @redirect_url = T.let("#{GitHub.url}#{redirect_url}", T.nilable(String))
    @feature = T.let(feature, T.nilable(String))
    @query_string = T.let(query_string, T.nilable(String))
    @end_date = T.let(end_date, T.nilable(Date))

    @title = T.let("Sorry, your #{feature} CSV couldn't be generated", T.nilable(String))
    @footer_text = T.let("You are receiving this email because you requested your #{feature} data.", T.nilable(String))

    premail(
      from: github_noreply,
      to: [GitHub.newsies.email(user, owner)],
      bcc: [],
      subject: "[GitHub] Sorry, your #{feature} CSV couldn't be generated",
    )
  end

  sig { params(business: Business, users_to_email: T::Array[::User], enterprise_teams: T::Array[::EnterpriseTeam]).void }
  def enterprise_security_manager_assignment(business:, users_to_email:, enterprise_teams:)
    email_batch_size = 500
    @enterprise_teams = T.let(enterprise_teams, T.nilable(T::Array[::EnterpriseTeam]))
    @business = T.let(business, T.nilable(Business))

    return unless users_to_email.present? && @enterprise_teams.present?

    @enterprise_team_link = T.let(nil, T.nilable(String))

    @title = if enterprise_teams.size > 1
      @enterprise_team_link = enterprise_security_managers_url(business.slug)
      T.let("Enterprise Security Manager teams have been granted access to your organization(s)", T.nilable(String))
    else
      @enterprise_team_link = enterprise_team_members_url(business.slug, enterprise_teams.first&.slug)
      T.let("An Enterprise Security Manager team has been granted access to your organization(s)", T.nilable(String))
    end
    @title = T.must(@title)

    @footer = T.let("You are receiving this email because you own an organization in the #{business.name} enterprise.", T.nilable(String))
    @footer = T.must(@footer)

    if users_to_email.size > email_batch_size
      users_to_email.each_slice(email_batch_size) do |users|
        premail(
          from: github_noreply,
          to: [],
          bcc: users.map { |user| GitHub.newsies.email(user) },
          subject: "[GitHub] #{@title}"
        )
      end
    else
      premail(
        from: github_noreply,
        to: [],
        bcc: users_to_email.map { |user| GitHub.newsies.email(user) },
        subject: "[GitHub] #{@title}"
      )
    end
  end
end
