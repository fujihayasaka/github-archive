# typed: strict
# frozen_string_literal: true

module CopilotSpaces::PageData::CopilotSpaceUserRole
  class Payload
    class Data < T::Struct
      const :actor_type, String
      const :display_login, T.nilable(String)
      const :slug, T.nilable(String)
      const :name, String
      const :avatar_url, String
      const :members_count, T.nilable(Integer)
      const :role, String
      const :actor_id, Integer
      const :disabled, T::Boolean
    end

    sig { params(role: Role, actor: T.any(User, Team), copilot_space: CopilotSpace, current_user: User).returns(Data) }
    def self.call(role:, actor:, copilot_space:, current_user:)
      new.call(role: role, actor: actor, copilot_space: copilot_space, current_user: current_user)
    end

    sig { params(role: Role, actor: T.any(User, Team), copilot_space: CopilotSpace, current_user: User).returns(Data) }
    def call(role:, actor:, copilot_space:, current_user:)
      Data.new(
        actor_type: actor.class.to_s.downcase,
        display_login: actor.try(:display_login),
        slug: actor.try(:slug),
        name: actor.is_a?(Team) ? actor.name : (actor.profile_name || actor.name),
        avatar_url: actor.primary_avatar_url(64),
        members_count: actor.try(:members_scope_count),
        role: role.name,
        actor_id: actor.id,
        disabled: current_user.id == actor.id || copilot_space.creator_id == actor.id
      )
    end
  end
end
