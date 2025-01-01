# typed: true
# frozen_string_literal: true

class Stafftools::Users::UserListItemComponent < ApplicationComponent
  attr_reader :user, :deleted

  def initialize(user:, deleted: false)
    @user = user
    @deleted = deleted
  end

  memoize def account
    user.is_a?(User) ? user : User.find_by(id: user_id)
  end

  def user_id
    if deleted
      user.data["id"] || user.user_id || user.org_id
    else
      account.id
    end
  end

  def login
    if deleted
      user.data["login"] || user.hit[:user] || user.hit[:org]
    else
      account.display_login
    end
  end

  def email
    user.data["email"] if deleted
  end

  def legal_hold
    deleted ? user.data["legal_hold"] : account.legal_hold
  end

  def was_org?
    if deleted
      user.action == "org.delete" || user.action == "org.soft_delete"
    else
      false
    end
  end

  def id_query
    base_id_query = "user_id:#{user_id} OR actor_id:#{user_id}"

    if was_org?
      if helpers.driftwood_ade_query?(current_user)
        "webevents | where (org != \"\" and org_id == #{user_id}) or user_id == #{user_id} or actor_id == #{user_id}"
      else
        "((_exists_:org AND org_id:#{user_id}) OR #{base_id_query})"
      end
    else
      if helpers.driftwood_ade_query?(current_user)
        "webevents | where user_id == #{user_id} or actor_id == #{user_id}"
      else
        "(#{base_id_query})"
      end
    end
  end

  def type_label
    if account&.is_a?(Organization) && account&.enterprise_managed_user_enabled?
      "EMU org"
    elsif account&.business.present?
      "Business org"
    elsif account&.is_a?(Organization) || was_org?
      "Org"
    elsif account&.is_a?(User) && account&.enterprise_managed_business.present?
      "EMU"
    else
      "User"
    end
  end

  memoize def soft_deleted?
    !!account&.soft_deleted?
  end

  memoize def belongs_to_a_soft_deleted_business?
    !!account&.belongs_to_a_soft_deleted_business?
  end

  def restore_or_recreate
    soft_deleted? ? "Restore" : "Recreate"
  end

  def has_name?
    return false if account.nil?

    account.profile_name.present? &&
      account.profile_name.downcase != account.login.downcase
  end
end
