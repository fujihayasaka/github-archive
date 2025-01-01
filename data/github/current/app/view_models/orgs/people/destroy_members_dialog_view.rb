# typed: true
# frozen_string_literal: true

class Orgs::People::DestroyMembersDialogView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :organization, :redirect_to_path, :selected_members

  # Should we show information about deleting private forks?
  #
  # Returns a boolean.
  def show_private_fork_info?
    selected_members.any? { |m| private_forks_count_for(m) > 0 }
  end

  def sorted_selected_member_ids
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

  def show_sso_warning?
    return false if organization.business&.enterprise_managed_user_enabled?
    return false if organization.enterprise_server_scim_enabled?
    return true if organization.saml_sso_enabled?
    return false if organization.business.nil?
    organization.business.saml_sso_enabled?
  end

  def dialog_cancel_button_id
    selected_members.size == 1 ? "remove-member-dialog-#{selected_members.first.id}" : "remove-from-org-dialog"
  end
end
