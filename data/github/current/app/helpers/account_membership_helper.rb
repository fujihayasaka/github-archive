# typed: strict
# frozen_string_literal: true

# Helpers for User/Organization/Business membership in things like the pre-release and
# developer programs.
module AccountMembershipHelper
  extend T::Sig
  extend T::Helpers

  requires_ancestor { ApplicationController }
  requires_ancestor { ApplicationController::AuthenticatedSystem }

  # Public: Array of enterprise accounts the current_user has admin access to.
  sig { returns(T::Array[Business]) }
  def adminable_businesses
    return [] unless logged_in?

    @adminable_businesses ||= T.let(current_user.businesses(membership_type: :admin).to_a, T.nilable(T::Array[Business]))
  end

  # Public: Array of org accounts the current_user has admin access to.
  sig { returns(T::Array[Organization]) }
  def adminable_organizations
    return [] unless logged_in?

    @adminable_organizations ||= T.let(current_user.organizations.select do |org|
      org.adminable_by?(current_user)
    end, T.nilable(T::Array[Organization]))
  end

  # Public: Array of user/org/enterprise accounts the current_user has admin
  # access to.
  #
  # include_businesses - Whether adminable enterprise accounts should be included.
  #                      Defaults to true. If your code is not ready to handle
  #                      enterprise accounts, pass `include_businesses: false`
  #                      instead.
  sig { params(include_businesses: T::Boolean).returns(T::Array[T.any(User, Organization, Business)]) }
  def adminable_accounts(include_businesses: true)
    return [] unless logged_in?
    return adminable_accounts_without_businesses unless include_businesses

    @adminable_accounts ||= T.let(
      adminable_accounts_without_businesses + adminable_businesses,
      T.nilable(T::Array[T.any(User, Organization, Business)])
    )
  end

  # Public: Array of user/org accounts the current_user has admin
  # access to.
  sig { returns(T::Array[User]) }
  def adminable_accounts_without_businesses
    return [] unless logged_in?

    @adminable_accounts_without_businesses ||= T.let(begin
      accounts = adminable_organizations.dup
      accounts.unshift current_user
      accounts
    end, T.nilable(T::Array[User]))
  end

  # Public: Array of org accounts the current_user has admin
  # access to and are not in a business.
  sig { returns(T::Array[Organization]) }
  def adminable_organizations_not_in_businesses
    return [] unless logged_in?

    @adminable_organizations_not_in_businesses ||= T.let(
      adminable_organizations.select { |org| org.business.nil? },
      T.nilable(T::Array[Organization])
    )
  end

  # Public: Current User, Organization, or Business being used for membership.
  sig { returns(T.nilable(T.any(User, Business))) }
  def account
    @account ||= T.let(find_account, T.nilable(T.any(User, Business)))
  end

  # Public: Find the user/org/business to grant membership.
  #
  # Accounts are found with this priority:
  # - The user_id (and optionally member_type) params are checked to find a
  #   user/org/business.
  # - The account param is checked for a user/org login.
  # - The business param is checked for a business slug.
  #
  sig { returns(T.nilable(T.any(User, Business))) }
  def find_account
    account = if params[:member_type].present?
      case params[:member_type]
      when "Business"
        Business.find_by(id: params[:user_id])
      when "User"
        User.find_by(id: params[:user_id])
      end
    else
      User.find_by(id: params[:user_id])
    end

    account ||= User.find_by(login: params[:account]) ||
        Business.find_by(slug: params[:business])

    if account && adminable_accounts.include?(account)
      account
    else
      current_user
    end
  end

  sig { returns(T.nilable(T.any(Symbol, User, Business))) }
  def target_for_conditional_access
    return :no_target_for_conditional_access unless account.present? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess

    account
  end
end
