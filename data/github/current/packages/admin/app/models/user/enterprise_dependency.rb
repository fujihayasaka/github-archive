# typed: true
# frozen_string_literal: true

module User::EnterpriseDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  requires_ancestor { User }

  # Public: Checks if an user wants their Enterprise contributions to be sent to
  #         Dotcom (to show on contribution graph / activity timeline)
  #
  # Returns a boolean
  def show_enterprise_contribution_counts_on_dotcom?
    DotcomUser.for(self).last_contributions_sync.present?
  end
  alias_method :show_enterprise_contribution_counts_on_dotcom, :show_enterprise_contribution_counts_on_dotcom?

  # Public: Given true/false, update user's preference on whether their Enterprise
  #         contribution counts are sent to dotcom
  def show_enterprise_contribution_counts_on_dotcom=(value)
    dotcom_user = DotcomUser.for(self)
    return if value && dotcom_user.last_contributions_sync.present?
    dotcom_user.update!(
      last_contributions_sync: value ? backfill_enterprise_contributions_from : nil,
    )
  end

  # Private: Timestamp since when we should backfill enterprise contribution
  #          counts into dotcom (for a user that just opted into doing so)
  def backfill_enterprise_contributions_from
    Time.now - EnterpriseContribution::BACKFILL_INTERVAL
  end
  private :backfill_enterprise_contributions_from

  class_methods do
    # Counts the number of users (excluding Organizations).
    #
    # Returns the Integer count of users without orgs.
    def count_without_orgs
      T.bind(self, T.class_of(User))
      self.where(
        "type = 'User' AND login NOT IN (?)", logins_to_exclude_from_counts
      ).count
    end

    # Counts the number of users that consume a license seat.
    #
    # Returns the Integer count of users who consume a seat.
    def count_seats_used
      T.bind(self, T.class_of(User))
      self.users_consuming_seats.count
    end

    # Returns the users consuming license seats.
    #
    # Returns an ActiveRecord::Relation representing users consuming seats.
    def users_consuming_seats
      T.bind(self, T.class_of(User))
      self.where(
        "type = 'User' AND login NOT IN (?) AND suspended_at IS NULL", logins_to_exclude_from_counts
      )
    end

    # Counts the number of organizations.
    #
    # Returns the Integer count of organizations.
    def count_with_only_orgs
      T.bind(self, T.class_of(User))
      self.where("type = 'Organization'").count
    end

    # Counts the number of users (excluding extras like ghost).
    #
    # Returns the Integer count of users without extra users.
    def count_without_extras
      T.bind(self, T.class_of(User))
      self.count - logins_to_exclude_from_counts.size
    end

    # User logins that should not contribute to counts.
    #
    # Returns an array of string logins.
    def logins_to_exclude_from_counts
      logins = [GitHub.ghost_user_login, GitHub.staff_user_login]

      logins.push(GitHub.actions_admin_login) if GitHub.actions_enabled?

      logins.push(GitHub.ghes_scim_admin_login) if GitHub.global_business&.enterprise_server_scim_enabled?

      logins
    end
  end
end
