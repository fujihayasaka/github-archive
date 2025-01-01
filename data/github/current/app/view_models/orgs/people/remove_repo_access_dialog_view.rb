# typed: true
# frozen_string_literal: true

class Orgs::People::RemoveRepoAccessDialogView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  MAX_DISPLAY_CASUALTIES = 100

  attr_reader :organization
  attr_reader :person
  attr_reader :repository
  attr_reader :repository_permissions
  attr_reader :active_only

  def casualties_count
    casualty_ids.size
  end

  def truncated_casualties
    @truncated_casualties ||= Repository.where(id: casualty_ids.first(MAX_DISPLAY_CASUALTIES)).includes(:owner)
  end

  def discarded_casualties_count
    [0, casualties_count - MAX_DISPLAY_CASUALTIES].max
  end

  def permission_after_revoking
    active_only ? repository_permissions.permission_after_revoking_active : nil
  end

  def removing_collaborator?
    if active_only
      repository_permissions.direct_ability_active?
    else
      repository_permissions.direct_ability.present?
    end
  end

  def teams
    if active_only
      repository_permissions.active_teams
    else
      repository_permissions.user_teams_with_access
    end
  end

  def will_retain_access?
    active_only && repository_permissions.permission_after_revoking_active.present?
  end

  private

  def casualty_ids
    if active_only
      repository_permissions.casualty_ids_from_revoking_active
    else
      repository_permissions.casualty_ids_from_revoking_all
    end
  end
end
