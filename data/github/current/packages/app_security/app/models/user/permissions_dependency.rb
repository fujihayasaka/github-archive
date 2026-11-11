# typed: true
# frozen_string_literal: true

module User::PermissionsDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  include Permissions::Participant

  requires_ancestor { User }

  # Public: Can this user have granular permissions on resources?
  sig { returns(T::Boolean) }
  def can_have_granular_permissions?
    false
  end

  # Public: Can this user have granular user permissions on resources?
  sig { returns(T::Boolean) }
  def can_have_granular_user_permissions?
    false
  end

  # Constraints to grant users a permission over the target.
  # This is called during the Ability and UserRole granting process.
  def can_be_granted_permission_over!(subject, action)
    return if GitHub.single_business_environment?
    return unless self.user? # orgs/bots/mannequins are not a thing here

    raise PermissionTFCARequiredError, "target of type #{subject.class.name} should implement :target_for_conditional_access" unless subject.respond_to?(:target_for_conditional_access)
    target_owner = subject.target_for_conditional_access

    raise PermissionTFCARequiredError, "target of type #{subject.class.name} must be owned by a valid entity" if target_owner == :no_target_for_conditional_access

    actor_is_enterprise_managed = self.is_enterprise_managed?

    # Unfortunately the methods are not homogeneous.
    # Calling org.is_enterprise_managed? on an EMU org will return false.
    # https://github.com/github/external-identities/issues/790
    target_is_enterprise_managed =
      case target_owner
      when Organization, Business
        target_owner.enterprise_managed_user_enabled?
      else
        target_owner.is_enterprise_managed?
      end

    # nor the actor nor the target are enterprise managed
    return if !actor_is_enterprise_managed && !target_is_enterprise_managed

    # special case the edge case for granting the initial user the admin ability
    emu_business_first_admin = target_is_enterprise_managed && subject.instance_of?(Business) && subject.admins.empty? && action.to_s == "admin"
    return if emu_business_first_admin

    if !actor_is_enterprise_managed && target_is_enterprise_managed
      raise PermissionGrantError.new("Can't grant permissions to a non-Enterprise Managed User over an Enterprise Managed #{subject.class.name}")
    end

    if actor_is_enterprise_managed && !target_is_enterprise_managed
      raise PermissionGrantError.new("Can't grant permissions to an Enterprise Managed User over an external #{subject.class.name}")
    end

    target_business =
      case target_owner
      when Organization
        target_owner.business || target_owner.associated_business_on_creation
      when Business
        target_owner
      else
        target_owner.enterprise_managed_business
      end

    if self.enterprise_managed_business != target_business
      raise PermissionGrantError.new("Can't grant permissions to an Enterprise Managed User over a different Managed Enterprise")
    end
  end
end
