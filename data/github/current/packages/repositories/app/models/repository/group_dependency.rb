# typed: false
# frozen_string_literal: true

module Repository::GroupDependency
  extend ActiveSupport::Concern

  included do
    has_one :group_map, class_name: "RepositoryGroupMap", dependent: :destroy
  end

  def group
    group_map&.repository_group
  end

  def group_path
    group&.group_path
  end

  def in_group?(group_path)
    RepositoryGroup.repository_in_group?(self, group_path)
  end

  def ensure_group
    group || join_group("")
  end

  # creates group if it does not exist
  def join_group(group_path)
    group = RepositoryGroup.find_or_create_group(owner:, group_path:)
    if self.group_map
      self.group_map.update(repository_group: group)
    else
      self.group_map = RepositoryGroupMap.new(repository: self, repository_group: group)
    end
    group
  end

  def leave_group
    # repos must be in a group
    join_group("")
  end

  def access_group_setting
    AccessGroupSetting.for_repository(self)
  end

  def fork_group_setting
    ForkGroupSetting.for_repository(self)
  end
end
