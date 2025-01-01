# typed: false
# frozen_string_literal: true

class SettingOrchestration < RepositoryOrchestration

  def self.from_group_setting(actor_id, setting, repository = nil)
    self.from_group(actor_id, setting.group, [setting], repository)
  end

  # if a repository is provided, only that single repository will be targeted
  def self.from_group(actor_id, group, settings, repository = nil)
    data = {
      actor_id:,
      group_path: group.group_path,
      types: settings.map(&:to_s),
    }.compact

    orchestration = nil
    owner = group.owner

    if repository
      orchestration = SettingRepositoryOrchestration.new(repository:, data:)
    elsif owner.is_a?(Organization)
      data[:organization_id] = owner.id
      orchestration = SettingOrganizationOrchestration.new(data:)
    else
      raise ArgumentError, "Invalid owner type: #{owner.class}"
    end

    orchestration.save!
    orchestration
  end

  def actor
    return nil if actor_id.blank?
    @actor ||= User.find_by_id(data[:actor_id])
  end

  def actor_id
    data[:actor_id]
  end

  def group_path
    data[:group_path]
  end

  def types
    data[:types]
  end

  def organization_id
    data[:organization_id]
  end

  def organization
    Organization.find_by(id: organization_id)
  end
end
