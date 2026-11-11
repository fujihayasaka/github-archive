# typed: strict
# frozen_string_literal: true

module GranularPermissionsHelper
  # Public: Given a hash of permissions, returns a hash of permissions grouped by
  # subject type.
  #
  # permissions - A hash of permissions, where the keys are subject types and the
  #               values are arrays of actions.
  # Examples
  #  - {"members"=>:read, "metadata"=>:read, "packages"=>:read}
  #
  #
  # Returns a hash of permissions grouped by subject type.
  #
  # Examples
  # - { :organization=>{"members"=>:read}, :repository=>{"metadata"=>:read, "packages"=>:read} },
  sig { params(permissions: T::Hash[String, Symbol]).returns(T::Hash[Symbol, T::Hash[String, Symbol]]) }
  def permissions_by_subject_type_hash(permissions)
    organization_subject_types = Organization::Resources.subject_types.to_set
    repository_subject_types = Repository::Resources.subject_types.to_set

    groups = permissions.group_by do |subject, _action|
      if organization_subject_types.include?(subject)
        :organization
      elsif repository_subject_types.include?(subject)
        :repository
      else
        :other
      end
    end

    groups.transform_values &:to_h
  end

  sig { params(action: T.nilable(T.any(Symbol, String))).returns(T::Boolean) }
  def action_blank?(action)
    action.blank? || action.nil? || action.to_sym == :none
  end

  # Public: Builds a hash from a given permission string
  #
  # Examples
  #
  #   parse_permission_string("organization_secrets_write") => { "organization_secrets" => :write }
  #
  #
  # The login part of this regexp was taken from User::LOGIN_REGEX
  sig { params(permission: T.nilable(String)).returns(T.nilable(T::Hash[String, Symbol])) }
  def parse_permission_string(permission)
    if permission.present?
      tokens = permission.split("_")
      if tokens.length > 1 && %w[read write].include?(tokens.last)
        permission = {}
        action = tokens.pop
        resource = tokens.join("_")
        return nil if resource.blank? || action_blank?(action)

        permission[resource] = T.must(action).to_sym
        permission
      end
    end
  end
end
