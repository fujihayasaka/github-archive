# typed: strict
# frozen_string_literal: true

module CopilotSpaces::PageData::CopilotSpace
  class IndexPayload
    class Data < T::Struct
      const :id, Integer
      const :name, String
      const :owner, String
      const :updatedAt, T.nilable(ActiveSupport::TimeWithZone)
      const :description, T.nilable(String)
      const :iconType, T.nilable(String)
      const :iconColor, T.nilable(String)
      const :ownerIsOrg, T::Boolean
      const :isEnterpriseManaged, T::Boolean
      const :ownerAvatar, T.nilable(String)
      const :ownerDisplayName, T.nilable(String)
      const :creator, T.nilable(String)
      const :visibility, T.nilable(String)
      const :editable, T::Boolean
      const :adminable, T::Boolean
      const :starred, T::Boolean
      const :baseRole, String
      const :shared, T::Boolean # Indicates whether the user-owned space is shared with the current user
      const :collaborative, T::Boolean # Indicates whether the space is accessible by multiple users with assigned roles
      const :public, T::Boolean # Indicates whether the user-owned space is public
      const :shareable, T::Boolean # Indicates whether the space can be shared with other users
    end

    sig { params(copilot_space: CopilotSpace, editable: T::Boolean, adminable: T::Boolean, shareable: T.nilable(T::Boolean)).returns(Data) }
    def self.call(copilot_space, editable: false, adminable: false, shareable: nil)
      new.call(copilot_space, editable: editable, adminable: adminable, shareable: shareable)
    end

    sig { params(copilot_space: CopilotSpace, editable: T::Boolean, adminable: T::Boolean, shareable: T.nilable(T::Boolean)).returns(Data) }
    def call(copilot_space, editable: false, adminable: false, shareable: nil)
      current_user = T.must(copilot_space.current_user)

      # Determine shareable value: use provided value or fall back to checking the space
      shareable_value = if shareable.nil?
        copilot_space.shareable?
      else
        shareable
      end

      Data.new(
        id: copilot_space.number,
        owner: copilot_space.owner.display_login,
        name: copilot_space.name,
        updatedAt: copilot_space.updated_at,
        description: copilot_space.description,
        iconType: copilot_space.icon_type,
        iconColor: copilot_space.icon_color,
        ownerIsOrg: copilot_space.owner.organization?,
        isEnterpriseManaged: copilot_space.enterprise_managed?,
        ownerAvatar: copilot_space.owner.primary_avatar_url,
        ownerDisplayName: copilot_space.owner.display_name || copilot_space.owner.display_login,
        creator: copilot_space.creator&.display_login,
        visibility: copilot_space.visibility,
        editable: editable,
        adminable: adminable,
        starred: copilot_space.starred_by?(current_user),
        baseRole: copilot_space.base_role,
        shared: copilot_space.shared_with?(current_user),
        collaborative: copilot_space.has_collaborators?,
        public: copilot_space.public?,
        shareable: shareable_value
      )
    end
  end
end
