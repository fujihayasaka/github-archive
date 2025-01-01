# typed: true
# frozen_string_literal: true

module Api::Serializer::CopilotSpaceDependency
  include Api::Serializer::UserDependency
  include Api::Serializer::OrganizationsDependency
  include Api::Serializer::RepositoriesDependency

  # Creates a Hash to be serialized to JSON.
  #
  # space   - CopilotSpace instance.
  # options - Hash
  #           :user - User viewing the space for permission filtering
  #
  # Returns a Hash if the CopilotSpace exists, or nil.
  def space_hash(space, options = {})
    return nil unless space
    options = Api::SerializerOptions.from(options)
    options[:user]

    {
      id: space.id,
      number: space.number,
      name: space.name,
      description: space.description,
      public: space.public?,
      owner: owner_hash(space.owner, options),
      creator: simple_user_hash(space.creator, options),
      created_at: space.created_at&.iso8601,
      updated_at: space.updated_at&.iso8601,
      html_url: space_html_url(space),
      api_url: space_api_url(space)
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

  def space_api_url(space)
    if space.owner.is_a?(User)
      url("/users/#{space.owner.login_for_api}/copilot-spaces/#{space.number}")
    elsif space.owner.is_a?(Organization)
      url("/orgs/#{space.owner.login_for_api}/copilot-spaces/#{space.number}")
    end
  end

  def space_html_url(space)
    if space.owner.is_a?(User)
      "https://github.com/copilot/spaces/#{space.owner.login_for_api}/#{space.number}"
    elsif space.owner.is_a?(Organization)
      "https://github.com/copilot/spaces/#{space.owner.login_for_api}/#{space.number}"
    end
  end
end
