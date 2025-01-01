# typed: strict
# frozen_string_literal: true

module Settings
  module EnterprisesControllerMethods
    extend T::Helpers

    MAX_PENDING_INVITATIONS = 10

    sig { params(user: T.nilable(User)).returns(T::Boolean) }
    def show_upsells?(user:)
      return false unless user
      return false if user.is_enterprise_managed?
      return false unless GitHub.billing_enabled?
      true
    end

    # Returns a list of businesses in alphabetical slug order.
    sig { params(user: T.nilable(User)).returns(T::Array[Business]) }
    def businesses(user:)
      return [] unless user
      if user.is_enterprise_managed?
        business = user.enterprise_managed_business
        business.present? ? [business] : []
      else
        user.businesses(include_unaffiliated: true).by_slug.to_a
      end
    end

    sig { params(user: T.nilable(User)).returns(T::Boolean) }
    def show_trial_information?(user:)
      return false unless user
      return false if user.is_enterprise_managed?
      return false unless GitHub.billing_enabled?
      true
    end

    sig { params(user: T.nilable(User)).returns(T::Array[BusinessAdministratorInvitation]) }
    def invitations(user:)
      return [] unless user
      return [] if user.is_enterprise_managed?
      return [] unless GitHub.billing_enabled?
      BusinessAdministratorInvitation.includes(:business)
        .pending
        .where(invitee_id: user.id)
        .limit(MAX_PENDING_INVITATIONS)
        .reject { |invite| invite.business.nil? || T.must(invite.business).spammy? }
    end
  end
end
