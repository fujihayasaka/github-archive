# typed: true
# frozen_string_literal: true

class MemexProjectCollaborator
  attr_reader :actor, :role

  def initialize(actor, role)
    @actor = actor
    @role = role
  end

  def to_hash
    {
      id: actor.id,
      actor_type: actor.class.to_s.downcase,
      login: actor.respond_to?(:display_login) ? actor.display_login : nil,
      slug: actor.respond_to?(:slug) ? actor.slug : nil,
      name: actor.respond_to?(:profile) && actor.profile.present? ? actor.profile.name : actor.name,
      avatarUrl: actor.primary_avatar_url(64),
      membersCount: actor.respond_to?(:members_scope_count) ? actor.members_scope_count : nil,
      role: role.name
    }
  end
end
