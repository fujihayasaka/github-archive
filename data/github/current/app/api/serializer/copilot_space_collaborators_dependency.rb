# typed: true
# frozen_string_literal: true

module Api::Serializer::CopilotSpaceCollaboratorsDependency
  extend T::Helpers
  include Api::Serializer::OrganizationsDependency
  include Api::Serializer::UserDependency

  requires_ancestor { Api::Serializer }

  # Creates a Hash to be serialized to JSON for a list of copilot space collaborators.
  #
  # data    - Hash with :user_roles key containing UserRole list
  # options - Hash
  #
  # Returns a Hash containing the serialized collaborators array.
  def copilot_spaces_collaborator_list_hash(data, options = {})
    user_roles = data.fetch(:user_roles, [])
    return { collaborators: [] } unless user_roles
    { collaborators: user_roles.map { |user_role| copilot_space_collaborator_hash(user_role, options) } }
  end

  # Creates a Hash to be serialized to JSON for a single copilot space collaborator.
  #
  # user_role - UserRole instance
  # options   - Hash
  #
  # Returns a Hash containing the serialized collaborator data.
  def copilot_space_collaborator_hash(user_role, options = {})
    actor = T.must(user_role.actor)

    # Map internal role names to public API role names
    public_role_name = case user_role.role.name
    when "custom_copilot_reader"
      "reader"
    when "custom_copilot_writer"
      "writer"
    when "custom_copilot_admin"
      "admin"
    else
      user_role.role.name # fallback to original name
    end

    base_hash = {
      role: public_role_name,
    }

    # Add actor-specific fields based on type
    if actor.is_a?(User)
      base_hash.merge(simple_user_hash(actor, options))
    elsif actor.is_a?(Team)
      base_hash.merge(team_hash(actor, options))
    else
      base_hash
    end
  end
end
