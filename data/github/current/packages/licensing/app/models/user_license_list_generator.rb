# typed: true
# frozen_string_literal: true

require "turboghas"

# This class is used to generate a list of all users on an Enterprise Server
# with the purpose of reporting the data to dotcom for account reconciliation

class UserLicenseListGenerator < UserListGenerator
  include GitHub::Memoizer

  attr_reader :include_full_user_info

  # Create a new user license list generator.
  def initialize(include_full_user_info: true, restrict_type: nil)
    @include_full_user_info = include_full_user_info
    # Make :suspended an unsupported restrict_type for this class.
    super(restrict_type: restrict_type == :suspended ? nil : restrict_type)
  end

  private

  # Overrides the user query to return
  #
  #  * id
  #  * login
  #  * primary email address
  #  * all other email addresses
  #  * profile name
  #  * role
  #  * creation_date
  def user_query
    Arel.sql <<-SQL, excluded_logins: User.logins_to_exclude_from_counts
      SELECT
        users.id,
        users.login,
        (SELECT name FROM profiles as up WHERE up.user_id = users.id LIMIT 1) as profile_name,
        IF(users.gh_role='staff', 'admin', 'user') as role,
        users.created_at
      FROM users
      WHERE users.type = 'User'
      AND users.login not in (:excluded_logins)
      AND users.suspended_at IS NULL
    SQL
  end

  # Completes the query results by returning a Hash for each user
  def complete_results(results)
    emails = UserEmail.where(user_id: results.map(&:first)).all

    results.map do |row|
      user_id, login, profile_name, role, created_at = *row

      full_user_info = {
          user_id: user_id,
          login: login,
          emails: user_emails(emails, user_id),
          profile_name: profile_name,
          site_admin: role == "admin" || role == "staff",
          created_at: created_at.to_formatted_s(:db)
      } if include_full_user_info

      {
        user_id: user_id,
        emails: user_emails(emails, user_id),
        # true, false or null if github/turboghas was not available
        using_advanced_security: advanced_security_user_ids&.include?(user_id),
        **full_user_info || {},
      }
    end
  end

  memoize def advanced_security_user_ids
    return Set.new unless GitHub.global_business.present? && GitHub::Enterprise.license.advanced_security_enabled

    resp = ::GitHub::Turboghas.client.get_active_committers(
      entity_id: GitHub.global_business.id,
      entity_type: :ENTITY_TYPE_BUSINESS,
    )

    unless resp&.error.nil?
      GitHub.logger.error(resp&.error)
      return nil
    end

    resp.data.users.map(&:id).to_set
  end

  def user_emails(emails, id)
    emails.select { |email| email.user_id == id }.map do |email|
      {
        email: email.email,
        primary: email.primary?,
      }
    end
  end
end
