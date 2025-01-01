# typed: strict
# frozen_string_literal: true

module CopilotSpaces::PageData::CopilotSpace
  class Payload
    class Data < T::Struct
      const :id, Integer
      const :oldId, Integer
      const :name, String
      const :slug, String
      const :owner, T.nilable(String)
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
      const :starred, T::Boolean
      const :starredUsers, T::Array[T.untyped]
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
        name: copilot_space.name,
        # The front end uses the presence of the owner to interpret the 'id' field as the number
        owner: owner,
        slug: copilot_space.slug,
        updatedAt: copilot_space.updated_at,
        description: copilot_space.description,
        generalInstructions: copilot_space.general_instructions,
        slugWithOwner: copilot_space.slug_with_owner,
        iconType: copilot_space.icon_type,
        iconColor: copilot_space.icon_color,
        resources: copilot_space.resources_react_payload(viewer: copilot_space.current_user, cap_filter: copilot_space.cap_filter),
        sizePercentage: copilot_space.size_percentage,
        ownerIsOrg: copilot_space.owner.organization?,
        ownerAvatar: copilot_space.owner.primary_avatar_url,
        ownerDisplayName: copilot_space.owner.profile_name || copilot_space.owner.display_login,
        creator: copilot_space.creator&.display_login,
        visibility: copilot_space.visibility,
        editable: copilot_space.adminable_by?(current_user),
        starred: copilot_space.starred_by?(current_user),
        starredUsers: copilot_space.starred_users_react_payload
      )
    end
  end
end
