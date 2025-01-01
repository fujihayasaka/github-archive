# typed: strict
# frozen_string_literal: true

module CopilotSpaces::PageData::CopilotSpace
  class IndexPayload
    class Data < T::Struct
      const :id, Integer
      const :oldId, Integer
      const :name, String
      const :owner, T.nilable(String)
      const :updatedAt, T.nilable(ActiveSupport::TimeWithZone)
      const :description, T.nilable(String)
      const :iconType, T.nilable(String)
      const :iconColor, T.nilable(String)
      const :ownerIsOrg, T::Boolean
      const :ownerAvatar, T.nilable(String)
      const :ownerDisplayName, T.nilable(String)
      const :visibility, T.nilable(String)
      const :editable, T::Boolean
      const :starred, T::Boolean
    end

    sig do
      params(copilot_space: CopilotSpace).returns(Data)
    end
    def self.call(copilot_space)
      new.call(copilot_space)
    end

    sig do
      params(copilot_space: CopilotSpace).returns(Data)
    end
    def call(copilot_space)
      current_user = copilot_space.current_user
      if current_user&.feature_enabled?(:custom_copilot_number_as_id) && copilot_space.number.present?
        id = copilot_space.number
        owner = copilot_space.owner.display_login
      else
        id = copilot_space.id
        owner = nil
      end

      Data.new(
        id: id,
        oldId: copilot_space.id,
        owner: owner,
        name: copilot_space.name,
        updatedAt: copilot_space.updated_at,
        description: copilot_space.description,
        iconType: copilot_space.icon_type,
        iconColor: copilot_space.icon_color,
        ownerIsOrg: copilot_space.owner.organization?,
        ownerAvatar: copilot_space.owner.primary_avatar_url,
        ownerDisplayName: copilot_space.owner.profile_name || copilot_space.owner.display_login,
        visibility: copilot_space.visibility,
        editable: copilot_space.adminable_by?(current_user),
        starred: copilot_space.starred_by?(current_user)
      )
    end
  end
end
