# typed: true
# frozen_string_literal: true

class Copilot::SeatManagement::UserSuggestionsView < AutocompleteView
  def org_member?(user)
    user.is_a?(User) && org_member_ids.include?(user.id)
  end

  private

  def org_member_ids
    @org_member_ids ||= organization.member_ids
  end

  def org_members_only?
    organization.enterprise_managed_user_enabled?
  end
end
