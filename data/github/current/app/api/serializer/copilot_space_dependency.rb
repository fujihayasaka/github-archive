# typed: true
# frozen_string_literal: true

module Api::Serializer::CopilotSpaceDependency
  include Api::Serializer::OrganizationsDependency
  include Api::Serializer::RepositoriesDependency

  # Creates a Hash to be serialized to JSON for a list of copilot spaces.
  #
  # data    - Hash with :spaces key containing array of Copilot Space instances
  # options - Hash
  #
  # Returns a Hash containing the serialized spaces array.
  def copilot_spaces_list_hash(data, options = {})
    spaces = data.fetch(:spaces, [])
    return { spaces: [] } unless spaces

    {
      spaces: spaces.map do |space|
        space_hash(space, options.dup)
      end
    }
  end

  # Creates a Hash to be serialized to JSON.
  #
  # space   - CopilotSpace instance.
  # options - Hash
  #
  # Returns a Hash if the CopilotSpace exists, or nil.
  def space_hash(space, options = {})
    return nil unless space
    options = Api::SerializerOptions.from(options)

    # Map internal base_role to API format
    api_base_role = CopilotSpaces::RoleMapping.internal_base_role_to_api(space.base_role)

    {
      id: space.id,
      number: space.number,
      name: space.name,
      description: space.description,
      general_instructions: space.general_instructions,
      base_role: api_base_role,
      owner: owner_hash(space.owner, options),
      creator: simple_user_hash(space.creator, options),
      created_at: space.created_at&.utc&.iso8601,
      updated_at: space.updated_at&.utc&.iso8601,
      html_url: space_html_url(space),
      api_url: space_api_url(space),
      resources_attributes: space.visible_resources.map { |resource| resource_hash(resource) }
    }
  end

  # Creates a Hash to be serialized to JSON for a single copilot space resource.
  #
  # resource - CopilotSpaceResource instance.
  # options  - Hash
  #
  # Returns a Hash if the resource exists, or nil.
  def copilot_space_resource_hash(resource, _options = {})
    return nil unless resource

    resource_hash(resource)
  end

  # Creates a Hash to be serialized to JSON for a list of copilot space resources.
  #
  # data    - Hash with :resources key containing array of CopilotSpaceResource instances
  # options - Hash
  #
  # Returns a Hash containing the serialized resources array.
  def copilot_space_resources_list_hash(data, _options = {})
    resources = data.fetch(:resources, [])

    {
      resources: resources.map { |resource| resource_hash(resource) }
    }
  end

  private

  def owner_hash(owner, options = {})
    if owner.is_a?(User)
      simple_user_hash(owner, options)
    elsif owner.is_a?(Organization)
      organization_hash(owner, options)
    else
      nil
    end
  end

  def resource_hash(resource)
    {
      id: resource.id,
      resource_type: resource.resource_type,
      copilot_chat_attachment_id: resource.copilot_chat_attachment_id,
      metadata: resource.metadata,
      created_at: resource.created_at&.utc&.iso8601,
      updated_at: resource.updated_at&.utc&.iso8601
    }
  end

  def role_actor_hash(actor, options = {})
    if actor.is_a?(User)
      simple_user_hash(actor, options)
    elsif actor.is_a?(Team)
      team_hash(actor, options)
    else
      nil
    end
  end

  def space_api_url(space)
    if space.owner.user?
      url("/user/#{space.owner.id}/copilot-spaces/#{space.number}")
    elsif space.owner.is_a?(Organization)
      url("/organizations/#{space.owner.id}/copilot-spaces/#{space.number}")
    end
  end

  def space_html_url(space)
    "https://github.com/copilot/spaces/#{space.owner.login_for_api}/#{space.number}"
  end
end
