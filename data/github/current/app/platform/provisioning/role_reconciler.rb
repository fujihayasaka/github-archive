# typed: true
# frozen_string_literal: true

class Platform::Provisioning::RoleReconciler
  # in the following role arrays, the GUID values are used by AAD and the name values are used by Okta
  # there might be multiple GUIDs for a given role due to the roles being removed and recreated in AAD
  ENTERPRISE_OWNER_ROLE = %w[981df190-8801-4618-a08a-d91f6206c954 enterprise_owner ba4987ab-a1c3-412a-b58c-360fc407cb10 bc596898-4b1a-4f79-983e-2d1665a806e2 36b03fcb-b8aa-40a7-b1c9-ce6a874b699f]
  BILLING_MANAGER_ROLE = %w[0e338b8c-cc7f-498a-928d-ea3470d7e7e3 billing_manager e6be2762-e4ad-4108-b72d-1bbe884a0f91]
  USER_ROLE = %w[27d9891d-2c17-4f45-a262-781a0e55c80a user 42154d7e-9044-47e5-96c9-d34a18c70cd9 c1f7d90b-571e-43b4-97b8-f0b5914eb43d]
  RESTRICTED_USER_ROLE = %w[1ebc4a02-e56c-43a6-92a5-02ee09b90824 restricted_user 58bf69fe-1eb6-488f-8d28-5f2647968bd3]
  GUEST_COLLABORATOR_ROLE = ["guest_collaborator"]

  HUMAN_READABLE_ROLES = {
    "Enterprise Owner": ENTERPRISE_OWNER_ROLE,
    "Billing Manager": BILLING_MANAGER_ROLE,
    "User": USER_ROLE,
    "Guest Collaborator": GUEST_COLLABORATOR_ROLE + RESTRICTED_USER_ROLE,
  }

  def self.human_readable_role(role)
    HUMAN_READABLE_ROLES.keys.find { |key| HUMAN_READABLE_ROLES[key].include?(role.downcase) }&.to_s || "Unrecognized role; defaults to \"User\""
  end

  def initialize(mapper:, target:, user_data:)
    @mapper = mapper
    @target = target
    @user_data = user_data
  end

  # Public: Reconcile a User's roles based on the roles from user data.
  #
  # Currently supported roles:
  #   - Enterprise Owner
  #   - Billing Manager
  #   - User
  #   - Restricted User
  #   - Guest Collaborator
  #
  # Returns nothing or an error when setting emails failed.
  def reconcile(identity:, actor_id:)
    return success(identity) unless @mapper.provisioning_enabled?(target: @target)
    return success(identity) unless identity

    actor = if actor_id.nil?
      # set actor to nil if there is no actor id passed in
      nil
    else
      User.find_by(id: actor_id)
    end

    if identity.user.suspended?
      remove_suspended_user_roles(identity: identity, actor: actor)
      GitHub.logger.info("User role reconciled - user is suspended",
        "gh.actor.id": actor&.id,
        "gh.external_identity.id": identity.id,
        "gh.user.id": identity.user_id,
        "gh.user.suspended": identity.user.suspended?,
      )
      success(identity)
    else
      assigned_roles = @user_data.roles.map(&:downcase)
      final_role = get_final_role(assigned_roles)

      GitHub.dogstats.increment(
        "external_identities.user_role_provisioning",
        tags: [
          "assigned_role:#{final_role}",
        ]
      )

      GitHub.logger.info("User role reconciled",
        "gh.actor.id": actor&.id,
        "gh.external_identity.id": identity.id,
        "gh.user.id": identity.user_id,
        "gh.user.final_role": final_role,
        "gh.user.suspended": identity.user.suspended?,
        "gh.user.assigned_roles": assigned_roles.map { |role| self.class.human_readable_role(role) },
      )

      assign_role(identity: identity, actor: actor, role: final_role)
    end
  end

  private

  # Private: Suspended users should not have an enterprise owner or billing manager role.
  #
  # Returns nothing.
  def remove_suspended_user_roles(identity:, actor:)
    @target.remove_owner(identity.user, actor: actor, send_notification: true) if @target.owner?(identity.user)
    @target.billing.remove_manager(identity.user, actor: actor, send_notification: true) if @target.billing_manager?(identity.user)
  end

  # Private: Determine if the roles assigned to the user intersect with the roles associated with the provided target.
  #
  # Returns a boolean indicating whether or not the two role arrays intersect.
  def roles_intersect?(assigned_roles, target_roles)
    (assigned_roles & target_roles).any?
  end

  # Private: Get the name of the role that should be assigned to this user.
  #
  # Roles are additive, so the most elevated role will always take precedence.
  #
  # Incoming Roles                                                  Final Role
  #
  # Enterprise Owner, Billing Manager, User                         Enterprise Owner
  # Enterprise Owner, Billing Manager                               Enterprise Owner
  # Enterprise Owner, User                                          Enterprise Owner
  # Billing Manager, User                                           Billing Manager
  # Enterprise Owner, Billing Manager, User, Guest Collaborator     Enterprise Owner
  # Enterprise Owner, Billing Manager, Guest Collaborator           Enterprise Owner
  # Enterprise Owner, User, Guest Collaborator                      Enterprise Owner
  # Enterprise Owner, Guest Collaborator                            Enterprise Owner
  # Billing Manager, User, Guest Collaborator                       Billing Manager
  # Billing Manager, Guest Collaborator                             Billing Manager
  # User, Guest Collaborator                                        User
  # Guest Collaborator                                              Guest Collaborator
  #
  # Returns a symbol representing the final role to be assigned.
  def get_final_role(assigned_roles)
    if roles_intersect?(assigned_roles, ENTERPRISE_OWNER_ROLE)
      :enterprise_owner
    elsif roles_intersect?(assigned_roles, BILLING_MANAGER_ROLE)
      :billing_manager
    elsif roles_intersect?(assigned_roles, USER_ROLE)
      :user
    elsif roles_intersect?(assigned_roles, GUEST_COLLABORATOR_ROLE + RESTRICTED_USER_ROLE)
      :guest_collaborator
    else
      # The default role is user. This is an edge case presented by Okta.
      :user
    end
  end

  # Private: Assign a role to a user or identity.
  #
  # Returns nothing.
  def assign_role(identity:, actor:, role:)
    if role == :enterprise_owner
      identity.update!(guest_collaborator: false) if identity.guest_collaborator?
      @target.billing.remove_manager(identity.user, actor: actor, send_notification: true) if @target.billing_manager?(identity.user)
      @target.add_owner(identity.user, actor: actor, send_email_notification: true) unless @target.owner?(identity.user)

      # Owner role takes precedence over billing manager so return
      return
    end

    @target.remove_owner(identity.user, actor: actor, send_notification: true) if @target.owner?(identity.user)

    if role == :billing_manager
      identity.update!(guest_collaborator: false) if identity.guest_collaborator?
      @target.billing.add_manager(identity.user, actor: actor, send_notification: true) unless @target.billing_manager?(identity.user)

      # Billing manager role takes precedence over user and guest collaborator / restricted user roles so return
      return
    end

    @target.billing.remove_manager(identity.user, actor: actor, send_notification: true) if @target.billing_manager?(identity.user)

    if role == :guest_collaborator
      # The "Guest Collaborator" roles live on the identity model.
      # Since roles are additive, and this is the most restrictive role, then it
      # should only be set to true when it's the only role present. The only
      # other role that could be present at this point is the "User" role.
      identity.update!(guest_collaborator: true) unless identity.guest_collaborator?
    else
      identity.update!(guest_collaborator: false) if identity.guest_collaborator?
    end

    success(identity)
  end

  # Private: generate a success status.
  #
  # Returns a successful provisioner status.
  def success(identity)
    Platform::Provisioning::ProvisionerStatus.success_identity_status(identity)
  end
end
