# typed: strict
# frozen_string_literal: true

module CopilotSpaces::PageData::CopilotSpace
  class Payload
    class Data < T::Struct
      const :id, Integer
      const :name, String
      const :slug, String
      const :owner, String
      const :updatedAt, T.nilable(ActiveSupport::TimeWithZone)
      const :description, T.nilable(String)
      const :generalInstructions, T.nilable(String)
      const :slugWithOwner, String
      const :iconType, T.nilable(String)
      const :iconColor, T.nilable(String)
      const :resources, T::Array[T.untyped]
      const :sizePercentage, T.nilable(Float)
      const :ownerIsOrg, T::Boolean
      const :ownerAvatar, T.nilable(String)
      const :ownerDisplayName, T.nilable(String)
      const :creator, T.nilable(String)
      const :visibility, T.nilable(String)
      const :editable, T::Boolean
      const :adminable, T::Boolean
      const :starred, T::Boolean
      const :starredUsers, T::Array[T.untyped]
      const :starredUsersCount, Integer
      const :baseRole, String
      const :shared, T::Boolean
      const :collaborative, T::Boolean
      const :public, T::Boolean
    end

    sig { params(copilot_space: CopilotSpace).returns(Data) }
    def self.call(copilot_space)
      new.call(copilot_space)
    end

    sig { params(copilot_space: CopilotSpace).returns(Data) }
    def call(copilot_space)
      current_user = T.must(copilot_space.current_user)
      cap_filter = T.must(copilot_space.cap_filter)

      Data.new(
        id: copilot_space.number,
        name: copilot_space.name,
        owner: copilot_space.owner.display_login,
        slug: copilot_space.slug,
        updatedAt: copilot_space.updated_at,
        description: copilot_space.description,
        generalInstructions: copilot_space.general_instructions,
        slugWithOwner: copilot_space.slug_with_owner,
        iconType: copilot_space.icon_type,
        iconColor: copilot_space.icon_color,
        resources: copilot_space.resources_react_payload(viewer: current_user, cap_filter: cap_filter),
        sizePercentage: copilot_space.size_percentage,
        ownerIsOrg: copilot_space.owner.organization?,
        ownerAvatar: copilot_space.owner.primary_avatar_url,
        ownerDisplayName: copilot_space.owner.profile_name || copilot_space.owner.display_login,
        creator: copilot_space.creator&.display_login,
        visibility: copilot_space.visibility,
        editable: copilot_space.editable_by?(current_user),
        adminable: copilot_space.adminable_by?(current_user),
        starred: copilot_space.starred_by?(current_user),
        starredUsers: copilot_space.starred_users_react_payload,
        starredUsersCount: copilot_space.starred_users_count,
        baseRole: copilot_space.base_role,
        collaborative: copilot_space.has_collaborators?,
        shared: copilot_space.shared_with?(current_user),
        public: copilot_space.public?
      )
    end
  end
end
