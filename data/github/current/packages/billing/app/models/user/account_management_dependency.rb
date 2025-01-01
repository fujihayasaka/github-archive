# typed: strict
# frozen_string_literal: true

# These methods are called from stafftools controllers/views that
# are belong to the account_management_stafftools service.
module User::AccountManagementDependency
  extend T::Helpers

  extend ActiveSupport::Concern

  requires_ancestor { ::User }

  # Public: The last date the user was active.
  #
  # Takes into account stratocaster events, active session events, access via PATs and SSH keys, and interactions on Enterprise.
  #
  sig { returns(T.nilable(Time)) }
  def last_active_timestamp
    [
      last_stratocaster_event_at,
      last_active_session_at,
      oauth_accesses.personal_tokens.order(accessed_at: :desc).pick(:accessed_at),
      public_keys.order(accessed_at: :desc).pick(:accessed_at),
      interaction&.last_active_at,
    ].compact.max
  end

  # Public: Returns the number of other users with the same login.
  sig { returns(Integer) }
  def duplicate_login_count
    @duplicate_login_count ||= T.let(User.where(login: login).count - 1, T.nilable(Integer))
  end

  # Public: Checks for another user with the same login
  sig { returns(T::Boolean) }
  def has_duplicate_login?
    (duplicate_login_count > 0)
  end

  # Public: Returns the numbers of UserEmail records belonging to some
  # other User but share an e-mail address with one of the current
  # user's UserEmail records.
  sig { returns(Integer) }
  def duplicate_email_count
    @duplicate_email_count ||= T.let(UserEmail.count_by_sql(["SELECT COUNT(*) FROM user_emails WHERE email IN (?) AND id NOT IN (?)", self.emails.map(&:email), self.emails.map(&:id)]), T.nilable(Integer))
  end

  # Public: Checks for another email record that shares its address with
  # one of this particular user's records.
  sig { returns(T::Boolean) }
  def has_duplicate_email?
    (duplicate_email_count > 0)
  end

  # Public - get all the repositories that have anonymous git access
  # enabled for this user/org
  sig { returns(ActiveRecord::Relation) }
  def anonymous_access_repositories
    public_repositories.with_anonymous_git_access
  end
end
