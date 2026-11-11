# typed: true
# frozen_string_literal: true

module Api::Serializer::StafftoolsRoleDependency
  extend T::Helpers

  requires_ancestor { T.class_of(Api::Serializer) }

  # Creates a Hash to be serialized to JSON.
  #
  # role    - StafftoolsRole instance
  # options -  Hash
  #
  # Returns a Hash if the StafftoolsRole exists, or nil.
  def stafftools_role(role, options = {})
    return nil unless role

    {
      id: role.id,
      name: role.name,
    }
  end

  # Creates a hash to be serialized to JSON.
  #
  # users - Users to include in the hash, stafftools_roles should be loaded
  #         on the users object to avoid an n+1
  #
  def stafftools_accesses(user, options = {})
    roles = user.stafftools_roles.map { |role| stafftools_role(role) }
    {
      user: simple_user_hash(user, options),
      stafftools_roles: roles,
    }
  end

  def stafftools_accesses_job(hash, options)
    hash
  end
end
