# typed: true
# frozen_string_literal: true

class Orgs::People::DestroyMembersDialogView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include GitHub::Memoizer

  attr_reader :organization, :redirect_to_path, :selected_members

  # Should we show information about deleting private forks?
  #
  # Returns a boolean.
  memoize def show_private_fork_info?
    selected_members.any? { |m| private_forks_count_for(m) > 0 }
  end

  memoize def sorted_selected_member_ids
    selected_members.map(&:id).sort.join(",")
  end

  def private_forks_count_for(user)
    @private_fork_counts ||= Repository.organization_member_private_forks(
      organization, selected_members).group(:owner_id).count

    @private_fork_counts[user.id] || 0
  end

  def show_private_forks_count_for?(user)
    private_forks_count_for(user) > 0
  end

  memoize def show_sso_warning?
    return false if organization.business&.enterprise_managed_user_enabled?
    return false if organization.enterprise_server_scim_enabled?
    return true if organization.saml_sso_enabled?
    return false if organization.business.nil?
    organization.business.saml_sso_enabled?
  end

  def dialog_cancel_button_id
    selected_members.size == 1 ? "remove-member-dialog-#{selected_members.first.id}" : "remove-from-org-dialog"
  end

  memoize def show_indirect_membership_info?
    return false unless organization.business.present?
    organization.business.erp_feature_enabled?(:enterprise_teams_org_assignment)
  end

  def user_has_only_indirect_membership?(user)
    return false unless show_indirect_membership_info?

    selected_users_with_indirect_membership.include?(user) &&
    !organization.member?(user, include_indirect_abilities: false)
  end

  memoize def selected_users_with_direct_membership
    selected_members.reject do |user|
      user_has_only_indirect_membership?(user)
    end
  end

  memoize def selected_users_with_indirect_membership
    selected_members.select do |user|
      Orgs.domain.teams.business_team_ids_with_assigned_orgs_for(
        user_id: user.id,
        organization_id: organization.id
      ).any?
    end
  end
end
