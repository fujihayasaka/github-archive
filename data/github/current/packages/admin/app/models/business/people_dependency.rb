# typed: true
# frozen_string_literal: true

module Business::PeopleDependency
  extend T::Helpers
  requires_ancestor { Business }

  include BusinessesHelper
  include Scientist

  ROLE_TYPE = {
    "member" => :member_without_admin,
    "owner" => :admin,
    "enterprise_owner" => :owner,
    "billing_manager" => :billing_manager,
    "guest_collaborator" => :guest_collaborator,
    "unaffiliated" => :unaffiliated,
    nil => :all,
  }.freeze

  FILTER_VALUE_NO_COST_CENTER = "no-cost-center"

  VALID_ORDER_FIELDS_FOR_USERS = %w(login created_at).freeze
  VALID_ORDER_FIELDS_FOR_BLAS_INVITATIONS = %w(created_at email).freeze
  VALID_ORDER_FIELDS_FOR_ADMIN_INVITATIONS = %w(created_at title).freeze
  VALID_ORDER_FIELDS_FOR_OUTSIDE_COLAB_INVITATIONS = %w(created_at).freeze
  VALID_ORDER_FIELDS_FOR_PENDING_MEMBER_INVITATIONS = %w(created_at title).freeze
  VALID_ORDER_FIELDS_FOR_FAILED_INVITATIONS = %w(created_at title).freeze
  VALID_DIRECTION_FIELDS = %w(asc desc).freeze

  USER_ACCOUNTS_THRESHOLD = 5000

  # Public: Returns filtered outside collaborators for the enterprise.
  #
  # login               - optional - The user login to find. If passed only exact matches for `users.login` will be returned
  # query               - optional — The user-provided query string with any filters (example: `visibility`) removed
  # order_by_field      - optional — String specifying the sort field. Supported: "login", "created_at". Default: "login".
  # order_by_direction  - optional — String specifying the sort direction. Supported: "asc", "desc". Default: "asc".
  # visibility          - optional — an Array of symbols, only return outside collaborators who have access to
  #                      repositories with this visibility.
  # organizations       - optional – an Array of strings, only return users who are outside collaborators on
  #                      repositories that belong to these organizations.
  # two_factor          - optional - a symbol (:enabled, :required, :disabled) only returns outside collaborators with this two-factor
  #                       authentication status. Anything else returns all outside collaborators.
  # viewer              - optional - the user requesting a list of filtered outside collaborators
  #
  # Returns an ActiveRecord::Relation
  def filtered_outside_collaborators(
    login: nil,
    query: nil,
    order_by_field: "login",
    order_by_direction: "asc",
    visibility: nil,
    two_factor: nil,
    organizations: nil,
    viewer: nil
  )
    # for easier handling of filter values from requests we'll assume nil here means "show everything"
    visibility ||= [:public, :private]
    org_ids = org_database_ids(organizations) if organizations.present?

    collaborators = outside_collaborators(
      on_repositories_with_visibility: visibility,
      with_two_factor_status: two_factor,
      organization_ids: org_ids
    )

    collaborators = if login.present?
      apply_login_filter(collaborators, login)
    else
      apply_user_query_filter(collaborators, query, viewer: viewer)
    end

    # Ignore invalid order by field and direction
    order_by_field = "login" unless VALID_ORDER_FIELDS_FOR_USERS.include?(order_by_field.to_s.downcase)
    order_by_direction = "asc" unless VALID_DIRECTION_FIELDS.include?(order_by_direction.to_s.downcase)
    collaborators.order(Arel.sql("users.#{order_by_field} #{order_by_direction}"))
  end

  # Public: Returns filtered members of the enterprise.
  #
  # viewer - required - the user requesting a list of filtered enterprise members
  #
  # optional arguments:
  # allow_filters_for_non_admin_viewer - when the viewer is not an admin or staff, this flag allows providing filters like organization_logins, deployment, license, etc.
  # organization_logins                - an Array of organization logins. only return users with organization membership in these orgs.
  # query                              - The user-provided query string with any filters (example: `visibility`) removed
  # order_by_field                     - String specifying the sort field. Supported: "login", "created_at". Default: "login".
  # order_by_direction                 - String specifying the sort direction. Supported: "asc", "desc". Default: "asc".
  # role                               - only return users matching this role, either `owner`, `member`, or nil
  # account_type                       - only return users matching the account type: nil, `local` (built-in auth), `SAML linked`, `SAML and SCIM linked`, or nil
  # deployment                         - only return users who exist in a specific type of deployment. either nil (all), cloud (GHEC), or server (GHES)
  # ignore_org_membership_visibility   - optionally ignore visibility rules, used to show _all_ enterprise members in stafftools to non enterprise members
  # license                            - only return users whose license is one of :volume, :enterprise, or both (nil)
  # two_factor                         - only return users whose two_factor status matches this value. either :enabled, :required, :secure, :insecure, :disabled, or nil
  # batched_scope                      - Boolean specifying whether to return a batched_scope instead of a regular scope. Default: false
  # batch_size                         - maximum number of ids in database query batches
  # cost_center                        - only return users whose cost center matches this value
  # skip_emu_admin                     - Always exclude EMU first owner
  # business_user_accounts_query       - Use business_user_account_filtered_members feature for query based on BusinessUserAccount
  # include_unaffiliated               - Include unaffiliated users in results for all
  #
  # Returns an ActiveRecord::Relation
  def filtered_members(
    viewer,
    allow_filters_for_non_admin_viewer: false,
    organization_logins: nil,
    query: nil,
    order_by_field: "login",
    order_by_direction: "asc",
    role: nil,
    account_type: nil,
    deployment: nil,
    ignore_org_membership_visibility: false,
    license: nil,
    two_factor: nil,
    batched_scope: false,
    batch_size: nil,
    cost_center: nil,
    skip_emu_admin: false,
    business_user_accounts_query: false,
    include_unaffiliated: false
  )
    organization_ids = org_database_ids(organization_logins)
    org_member_type = ROLE_TYPE[role]

    bua_filtered_members = business_user_accounts_query ||
      self.feature_enabled?(:business_user_account_filtered_members, memoize: false) ||
      viewer&.feature_enabled?(:business_user_account_filtered_members)
    # unaffiliated only exists on emu-enabled businesses or where the unaffiliated_user_accounts
    # feature flag is enabled
    org_member_type = :all if org_member_type == :unaffiliated && !supports_unaffiliated_user_accounts?
    # guest collaborators only exist in emu-enabled businesses
    org_member_type = :all if org_member_type == :guest_collaborator && !enterprise_managed_user_enabled?

    filter_options = {
      allow_filters_for_non_admin_viewer:,
      organization_logins:,
      query:,
      organization_ids:,
      org_member_type:,
      account_type:,
      deployment:,
      ignore_org_membership_visibility:,
      license:,
      two_factor:,
      cost_center:,
    }
    # Use new filtered members implementation when filtering for copilot licenses
    bua_filtered_members = true if filter_options[:license].to_s.end_with?("copilot")

    actor_can_read_members = actor_can_read_members?(viewer)

    if !is_allowed_to_use_filters?(viewer, filter_options) || incompatible_filter_criteria?(filter_options)
      if GitHub.single_business_environment?
        return User.none
      end
      return BusinessUserAccount.none
    end

    # Ignore invalid order by field and direction
    order_by_field = "login" unless VALID_ORDER_FIELDS_FOR_USERS.include?(order_by_field.to_s.downcase)
    order_by_direction = "asc" unless VALID_DIRECTION_FIELDS.include?(order_by_direction.to_s.downcase)
    order = nil

    # Get business user accounts associated with the user scope, and include enterprise installation accounts if any
    # For GHES, there is no need to get these business user accounts, so just use the current users_scope
    if GitHub.single_business_environment?
      scope = build_user_scope(viewer, filter_options)
      order = "#{scope.table_name}.#{order_by_field} #{order_by_direction}"
      scope.order(Arel.sql(order))
    elsif bua_filtered_members
      scope = user_accounts.exclusive_no_roles(:outside_collaborator).and(BusinessUserAccount.exclusive_no_roles(:suspended))
      # Filter out ghost user
      exclude_ids = [User.ghost.id]
      # Filter by member type
      case org_member_type
      when :member_without_admin
        scope = scope.and(BusinessUserAccount.roles([:member]).or(BusinessUserAccount.roles(:server_member).no_roles(:server_admin)))
        scope = scope.and(BusinessUserAccount.exclude_unaffiliated_role) unless include_unaffiliated
        admin_ids = organization_member_ids(action: :admin)
        exclude_ids += admin_ids if admin_ids.any?
      when :admin
        scope = scope.and(BusinessUserAccount.roles([:server_admin]).or(BusinessUserAccount.where(user_id: organization_member_ids(action: :admin))))
      when :unaffiliated
        if enterprise_managed_user_enabled?
          scope = scope.unaffiliated_role
        else
          scope = scope.exclusive_unaffiliated_role
        end
      else
        scope = scope.roles(org_member_type) if org_member_type != :all
      end
      # Exclude users who aee not org-members if organization_login filter is enabled
      if organization_ids&.any?
        # TODO: Avoid large IN query
        scope = scope.where(user_id: visible_organization_members_for(
          viewer,
          type: Business::ADMIN_ROLES.include?(org_member_type) ? :all : org_member_type,
          ignore_visibility: enterprise_managed_user_enabled? ? true : ignore_org_membership_visibility,
          org_ids: organization_ids,
        ).pluck(:id))
      end
      # Filter by deployment
      case deployment
      when "cloud"
        scope = scope.where.not(user_id: nil)
        scope = scope.and(BusinessUserAccount.exclusive_no_roles(:server_admin)).and(BusinessUserAccount.exclusive_no_roles(:server_member)) unless enterprise_managed_user_enabled?
        scope = scope.and(BusinessUserAccount.exclude_unaffiliated_role) if !include_unaffiliated && !enterprise_managed_user_enabled?
      when "server"
        scope = scope.and(BusinessUserAccount.roles(:server_member).or(BusinessUserAccount.roles(:server_admin)))
      end
      # Filter out admins and non-visible member if user does not have the correct permissions
      if !actor_can_read_members && !seats_plan_basic? && org_member_type != :member_without_admin && !ignore_org_membership_visibility && !enterprise_managed_user_enabled?
        scope = scope.roles(:member).where(user_id: visible_organization_members_for(
          viewer,
          type: Business::ADMIN_ROLES.include?(org_member_type) ? :all : org_member_type,
          ignore_visibility: ignore_org_membership_visibility,
        ).pluck(:id))
      # Hide non-org-member users when ignore_org_membership_visibility is used
      elsif ignore_org_membership_visibility && !enterprise_managed_user_enabled? && org_member_type != :unaffiliated
        scope = scope.roles(:member)
      end
      # Filter out EMU admin
      scope = scope.no_roles(:emu_admin) if enterprise_managed_user_enabled? && ((!actor_can_read_members && !viewer.site_admin? && org_member_type != :owner) || skip_emu_admin)
      # Filter by license and exclude billing managers not consuming a license
      scope = filter_by_license(scope, license, bua_filtered_members: true) if license
      # Filter by 2FA status
      scope = filter_user_accounts_by_two_factor_status(scope, two_factor)
      # Filter by cost center
      scope = filter_user_accounts_by_cost_center(scope, cost_center) if !cost_center.nil? && !self.cost_centers.nil?
      # Query for user login, profile or email
      scope = apply_user_query_filter(scope, query, viewer: viewer)
      # Filter out spammy users
      scope = scope.where(spammy: false) if !actor_can_read_members && !enterprise_managed_user_enabled?
      # Filter all excluded users
      scope = scope.and(BusinessUserAccount.where.not(user_id: exclude_ids).or(BusinessUserAccount.where(user_id: nil)))
      # Sort order
      order = "#{scope.table_name}.#{order_by_field} #{order_by_direction}"
      scope.order(Arel.sql(order))
    else
      users_scope = build_user_scope(viewer, filter_options, skip_emu_admin: skip_emu_admin || batched_scope)
      if batched_scope && (enterprise_managed_user_enabled? || org_member_type != :unaffiliated)
        user_ids = users_scope.pluck(:id)
        if enterprise_managed_user_enabled? && filter_options[:org_member_type] != :guest_collaborator && filter_options[:org_member_type] != :member_without_admin
          user_ids += User.where(
            login: User.standardize_login(self.shortcode, suffix: User::EnterpriseManagedDependency::ADMIN_SUFFIX)
          ).pluck(:id)
        end

        build_business_user_batched_scope(user_ids, filter_options, order_by_field, order_by_direction, batch_size)
      else
        scope = build_business_user_scope(users_scope, filter_options)
        order = "#{scope.table_name}.#{order_by_field} #{order_by_direction}"
        scope.order(Arel.sql(order))
      end
    end
  end

  # Public: Returns the ids of all (direct or organization) members and server users of the
  # enterprise.
  #
  # Returns an Array of User IDs
  def all_member_ids
    if GitHub.single_business_environment?
      single_business_members.pluck(:id)
    else
      abilities = if feature_enabled?(:batch_business_org_abilities) || feature_enabled?(:run_business_org_abilities_experiment)
        business_org_abilities do |scope|
          scope.pluck(:actor_id)
        end
      else
        business_org_abilities.pluck(:actor_id)
      end
      Set.new(owner_ids + abilities + enterprise_installation_user_ids).to_a - [User.ghost.id]
    end
  end

  # Public: Returns all guest collaborators of the enterprise.
  #
  # Returns an ActiveRecord::Relation
  def all_guest_collaborators
    return [] unless enterprise_managed_user_enabled? && external_provider
    User
      .joins(:external_identities)
      .where(external_identities: {
        provider_id: self.external_provider.id,
        provider_type: self.external_provider.class.name,
        disabled_at: nil
      })
      .where(external_identities: { guest_collaborator: true })
  end

  # Public: get the administrators (owners and billing managers) for this business.
  #
  # query:              - optional - The user-provided query string with any filters (example: `role`) removed
  # order_by_field      - optional — String specifying the sort field. Supported: "login", "created_at". Default: "login".
  # order_by_direction  - optional — String specifying the sort direction. Supported: "asc", "desc". Default: "asc".
  # role                - optional - Only return admins with the given role. Valid values: [:owner, :billing_manager]
  #                                  A nil role will return all administrators.
  #                                  Invalid roles will be ignored and treated as nil.
  # organization_logins - optional - an Array of organization logins. only return admins with organization
  #                                  membership in these orgs.
  # two_factor          - optional - a symbol only returns outside collaborators with this two-factor
  #                       authentication status. Valid values: :enabled, :required, :disabled
  # viewer              - optional - the user requesting a list of admins
  #
  # Returns an ActiveRecord::Relation for the business' administrators
  def admins(
    query: nil,
    order_by_field: "login",
    order_by_direction: "asc",
    role: nil,
    organization_logins: nil,
    two_factor: nil,
    viewer: nil)

    role = nil unless Business::ADMIN_ROLES.include?(role&.to_sym&.downcase)
    admins_scope = admins_with_role(role)
    admins_scope = apply_user_query_filter(admins_scope, query, viewer: viewer)

    org_ids_filter = org_database_ids(organization_logins)
    return User.none if org_ids_filter.blank? && organization_logins.present?

    admins_scope = filter_by_organization(admins_scope, org_ids_filter)

    # Preventing breaking backwards compatibility by allowing :required to use old filter
    admins_scope = filter_users_by_two_factor_status(admins_scope, two_factor)

    # Ignore invalid order by field and direction
    order_by_field = "login" unless VALID_ORDER_FIELDS_FOR_USERS.include?(order_by_field.to_s.downcase)
    order_by_direction = "asc" unless VALID_DIRECTION_FIELDS.include?(order_by_direction.to_s.downcase)
    admins_scope.order(Arel.sql("users.#{order_by_field} #{order_by_direction}"))
  end

  # Public: retrieve the pending administrator invitations for this business.
  #
  # login               - optional - The user login to find. If passed only exact matches for `users.login` will be returned
  # query:              - optional - The user-provided query string with any filters (example: `role`) removed
  # order_by_field      - optional — String specifying the sort field. Supported: "created_at". Default: "created_at".
  # order_by_direction  - optional — String specifying the sort direction. Supported: "asc", "desc". Default: "desc".
  # role:               - optional - an Array of symbols, only return invitations for the specified role;
  #                                  Valid values: [:owner, :billing_manager]
  #
  # Returns: ActiveRecord::Relation of BusinessAdministratorInvitation's
  def pending_admin_invitations(
      login: nil,
      query: nil,
      order_by_field: nil,
      order_by_direction: nil,
      role: nil
  )
    role ||= Business::ADMIN_ROLES
    admin_invitations = invitations.pending.
                          left_joins(:invitee).
                          with_business_role(*role)

    query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)
    admin_invitations = if login.present?
      apply_login_filter(admin_invitations, login)
    elsif query.present?
      admin_invitations.left_joins(invitee: :profile)
                              .where(["users.login LIKE :query OR profiles.name LIKE :query OR business_member_invitations.email LIKE :query",
                                      { query: "%#{query}%" }])
                              .references(:users, :profile)
    else
      admin_invitations
    end

    # Ignore invalid order by field and direction if provided
    order_by_field = "created_at" unless VALID_ORDER_FIELDS_FOR_ADMIN_INVITATIONS.include?(order_by_field.to_s.downcase)
    order_by_direction = "desc" unless VALID_DIRECTION_FIELDS.include?(order_by_direction.to_s.downcase)

    if order_by_field.to_s.downcase == "title"
      admin_invitations = admin_invitations.left_joins(invitee: :profile)
      order = "COALESCE(profiles.name, users.login, business_member_invitations.email)"
    else
      order = "business_member_invitations.#{order_by_field}"
    end
    order += " #{order_by_direction}"
    admin_invitations.order(Arel.sql(order))
  end

  # Public: retrieve the pending unaffiliated member invitations for this business.
  #
  # login               - optional - The user login to find. If passed only exact matches for `users.login` will be returned
  # query:              - optional - The user-provided query string with any filters (example: `role`) removed
  # order_by_field      - optional — String specifying the sort field. Supported: "created_at". Default: "created_at".
  # order_by_direction  - optional — String specifying the sort direction. Supported: "asc", "desc". Default: "desc".
  #
  # Returns: ActiveRecord::Relation of BusinessAdministratorInvitation's
  def pending_unaffiliated_invitations(
      login: nil,
      query: nil,
      order_by_field: nil,
      order_by_direction: nil
  )
    unaffiliated_invitations = invitations.pending.
                                 left_joins(:invitee).
                                 with_business_role(:unaffiliated)

    query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)
    unaffiliated_invitations = if login.present?
      apply_login_filter(unaffiliated_invitations, login)
    elsif query.present?
      unaffiliated_invitations.left_joins(invitee: :profile)
                              .where(["users.login LIKE :query OR profiles.name LIKE :query OR business_member_invitations.email LIKE :query",
                                      { query: "%#{query}%" }])
                              .references(:users, :profile)
    else
      unaffiliated_invitations
    end

    # Ignore invalid order by field and direction if provided
    order_by_field = "created_at" unless VALID_ORDER_FIELDS_FOR_ADMIN_INVITATIONS.include?(order_by_field.to_s.downcase)
    order_by_direction = "desc" unless VALID_DIRECTION_FIELDS.include?(order_by_direction.to_s.downcase)

    if order_by_field.to_s.downcase == "title"
      unaffiliated_invitations = unaffiliated_invitations.left_joins(invitee: :profile)
      order = "COALESCE(profiles.name, users.login, business_member_invitations.email)"
    else
      order = "business_member_invitations.#{order_by_field}"
    end
    order += " #{order_by_direction}"
    unaffiliated_invitations.order(Arel.sql(order))
  end

  # Public: Get the pending organization member invitations for any
  # organizations that are part of the business.
  #
  # NOTE: when organization invitations are bypassed and members are added directly to
  # organizations in the Enterprise environment, this method always returns
  # `OrganizationInvitation.none` even if legacy invitations from GHE 2.3 and
  # earlier still exist.
  #
  # login               - optional - The user login to find. If passed only exact matches for `users.login` will be returned
  # query               - optional - The user-provided query string with any filters (example: `role`) removed
  # organizations       - optional - an Array of organization logins (String). Only return invitations for these orgs. Default: nil.
  # invitation_source   - optional - String specifying the invitation source to filter on. Default: nil.
  # order_by_field      - optional — String specifying the sort field. Supported: "created_at". Default: nil.
  # order_by_direction  - optional — String specifying the sort direction. Supported: "asc", "desc". Default: nil.
  #
  # Returns an ActiveRecord::Relation
  def pending_member_invitations(
    login: nil,
    query: nil,
    organizations: nil,
    invitation_source: nil,
    order_by_field: nil,
    order_by_direction: nil
  )
    return OrganizationInvitation.none if GitHub.bypass_org_invites_enabled?
    return OrganizationInvitation.none if enterprise_managed_user_enabled?

    scope = OrganizationInvitation.from("organization_invitations FORCE INDEX(org_id_failed_at_accepted_at_cancelled_at_role_invitee_id)").
      pending.
      left_joins(:invitee).
      except_with_role(:billing_manager)

    scope = if organizations.blank?
      scope
        .joins("LEFT JOIN `business_organization_memberships` ON `business_organization_memberships`.`organization_id` = `organization_invitations`.`organization_id`")
        .where("`business_organization_memberships`.`business_id` = ?", id)
    else
      scope.where(organization_id: org_database_ids(organizations))
    end

    scope = scope.with_invitation_source(invitation_source.to_sym) if invitation_source.present?

    query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)
    scope = if login.present?
      apply_login_filter(scope, login)
    elsif query.present?
      scope.left_joins(invitee: :profile)
        .where(["users.login LIKE :query OR profiles.name LIKE :query OR organization_invitations.email LIKE :query", { query: "%#{query}%" }])
    else
      scope
    end

    # Ignore invalid order by field and direction if provided
    order_by_field = nil unless VALID_ORDER_FIELDS_FOR_PENDING_MEMBER_INVITATIONS.include?(order_by_field.to_s.downcase)
    order_by_direction = nil unless VALID_DIRECTION_FIELDS.include?(order_by_direction.to_s.downcase)
    if order_by_field.present? && order_by_direction.present?
      if order_by_field.to_s.downcase == "title"
        scope = scope.left_joins(invitee: :profile)
        order = "COALESCE(profiles.name, users.login, organization_invitations.email)"
      else
        order = "organization_invitations.#{order_by_field}"
      end
      order += " #{order_by_direction}"

      # Add created_at as second clause if not already ordering by created_at
      # see tests "rolls up invitations to the same user across different organizations; ensures that the date of the business invite is that of the last org invite that was sent to the user"
      unless order_by_field.to_s.downcase == "created_at"
        created_at_order_by_direction = order_by_direction.to_s.downcase == "asc" ? "DESC" : "ASC"
        order += ", organization_invitations.created_at #{created_at_order_by_direction}"
      end

      scope = scope.order(Arel.sql(order))
    end

    scope
  end
  alias_method :pending_invitations, :pending_member_invitations

  def failed_invitations(
    login: nil,
    query: nil,
    order_by_field: nil,
    order_by_direction: nil
  )
    return OrganizationInvitation.none if GitHub.bypass_org_invites_enabled?

    scope = OrganizationInvitation.failed.left_joins(:invitee)
    scope = scope.where("cancelled_at IS NULL")

    scope = scope.where(organization_id: organization_ids)

    query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)
    scope = if login.present?
      apply_login_filter(scope, login)
    elsif query.present?
      scope.left_joins(invitee: :profile)
        .where(["users.login LIKE :query OR profiles.name LIKE :query OR organization_invitations.email LIKE :query", { query: "%#{query}%" }])
    else
      scope
    end

    # Ignore invalid order by field and direction if provided
    order_by_field = nil unless VALID_ORDER_FIELDS_FOR_FAILED_INVITATIONS.include?(order_by_field.to_s.downcase)
    order_by_direction = nil unless VALID_DIRECTION_FIELDS.include?(order_by_direction.to_s.downcase)
    if order_by_field.present? && order_by_direction.present?
      if order_by_field.to_s.downcase == "title"
        scope = scope.left_joins(invitee: :profile)
        order = "COALESCE(profiles.name, users.login, organization_invitations.email)"
      else
        order = "organization_invitations.#{order_by_field}"
      end
      order += " #{order_by_direction}"

      # Add created_at as second clause if not already ordering by created_at
      unless order_by_field.to_s.downcase == "created_at"
        created_at_order_by_direction = order_by_direction.to_s.downcase == "asc" ? "DESC" : "ASC"
        order += ", organization_invitations.created_at #{created_at_order_by_direction}"
      end

      # Add id as last clause to make sort consistent when reversed and similar dates
      order += ", organization_invitations.id #{order_by_direction}"

      scope = scope.order(Arel.sql(order))
    end

    scope
  end

  def filtered_failed_invitations(
    query: nil,
    order_by_field: nil,
    order_by_direction: nil
  )
    order_by_field = "created_at" unless VALID_ORDER_FIELDS_FOR_FAILED_INVITATIONS.include?(order_by_field.to_s.downcase)
    order_by_direction = "desc" unless VALID_DIRECTION_FIELDS.include?(order_by_direction.to_s.downcase)

    failed_invitations = failed_invitations(
      query: query,
      order_by_field: order_by_field,
      order_by_direction: order_by_direction,
    ).limit(Business::PendingInvitation::QUERY_LIMIT)

    failed_invitations = failed_invitations
      .includes(:organization, invitee: [:primary_user_email, :profile])
      .map do |org_invite|
        source = Business::PendingInvitation::SOURCES[:enterprise]
        Business::PendingInvitation.new(
          business: self,
          original_object: org_invite,
          invitee: org_invite.invitee,
          source: source
        )
      end.compact.uniq
  end

  # Public: Returns filtered pending member invitations of the enterprise using preloaded queries.
  #
  # optional arguments:
  # query               - The user-provided query string with any filters (example: `visibility`) removed
  # license             - only return users whose license is one of :enterprise, :vss_bundle, or both (nil)
  # organizations       - an Array of organizations. only return invitations for these orgs. Default: nil.
  # invitation_source   - String specifying the invitation source to filter on. Default: nil.
  # order_by_direction  - String specifying the sort direction. Supported: "asc", "desc". Default: "asc".
  #
  # Returns an array of PendingInvitations
  def filtered_pending_invitations(
    query: nil,
    license: nil,
    organizations: nil,
    invitation_source: nil,
    order_by_direction: nil,
    order_by_field: nil
  )
    order_by_field = "created_at" unless VALID_ORDER_FIELDS_FOR_PENDING_MEMBER_INVITATIONS.include?(order_by_field.to_s.downcase)
    order_by_direction = "desc" unless VALID_DIRECTION_FIELDS.include?(order_by_direction.to_s.downcase)

    pending_bundled_license_assignments = if organizations.blank? && invitation_source.blank?
      pending_bla_order_field = order_by_field
      if pending_bla_order_field.to_s.downcase == "title"
        pending_bla_order_field = "email"
      end
      pending_bundled_license_assignments(
        query: query,
        order_by_field: pending_bla_order_field,
        order_by_direction: order_by_direction,
      ).limit(Business::PendingInvitation::QUERY_LIMIT / 2)
    else
      []
    end

    pending_member_invitations = pending_member_invitations(
      query: query,
      organizations: organizations,
      invitation_source: invitation_source,
      order_by_field: order_by_field,
      order_by_direction: order_by_direction,
    ).limit(Business::PendingInvitation::QUERY_LIMIT / 2)

    blas = pending_bundled_license_assignments.map do |bla|
      Business::PendingInvitation.new(
        business: self,
        original_object: bla,
        email: bla.email,
        source: Business::PendingInvitation::SOURCES[:vss]
      )
    end.compact

    matching_emails = []
    org_invites = pending_member_invitations
      .includes(:organization, invitee: [:primary_user_email, :profile])
      .map do |org_invite|
        if bla = blas.find { |bla| bla.email == org_invite.email || bla.email == org_invite.invitee&.email }
          source = Business::PendingInvitation::SOURCES[:vss]
          matching_emails << bla.email
        else
          source = Business::PendingInvitation::SOURCES[:enterprise]
        end
        Business::PendingInvitation.new(
          business: self,
          original_object: org_invite,
          invitee: org_invite.invitee,
          source: source
        )
      end.compact.uniq

    blas.reject! { |bla| matching_emails.uniq.include?(bla.email) }

    pending_invitations = org_invites + blas

    if license
      pending_invitations = case license
      when "enterprise"
        pending_invitations.select { |invite| invite.source == Business::PendingInvitation::SOURCES[:enterprise] }
      when "vss_bundle"
        pending_invitations.select { |invite| invite.source == Business::PendingInvitation::SOURCES[:vss] }
      end
    end

    if order_by_field.to_s.downcase == "title"
      pending_invitations = pending_invitations.sort_by { |invite| invite.invitee&.profile&.name&.downcase || invite.invitee&.login&.downcase || invite.original_object.email.downcase }
    elsif order_by_field.to_s.downcase == "created_at"
      pending_invitations = pending_invitations.sort_by { |invite| invite.original_object.created_at }
    end

    pending_invitations.reverse! if order_by_direction == "desc"
    pending_invitations
  end

  # Public: Returns the total count of unique users that have been invited to become members of
  # the enterprise.
  #
  # Returns an Integer
  def unique_pending_member_invitation_count
    invitations = pending_member_invitations
    invitations.where(email: nil).group(:invitee_id).count.size +
      invitations.where.not(email: nil).group(:email).count.size
  end

  # Public: Returns the total count of unique users that have a failed invitation to become members of
  # the enterprise.
  #
  # Returns an Integer
  def unique_failed_invitation_count
    invitations = failed_invitations
    invitations.where(email: nil).group(:invitee_id).count.size +
      invitations.where.not(email: nil).group(:email).count.size
  end

  # Public: Get the pending bundled license assignments for the business.
  #
  # query:              - optional - The user-provided query string with any filters (example: `role`) removed
  # order_by_field      - optional — String specifying the sort field. Supported: "created_at". Default: nil.
  # order_by_direction  - optional — String specifying the sort direction. Supported: "asc", "desc". Default: nil.
  #
  # Returns an ActiveRecord::Relation
  def pending_bundled_license_assignments(
    query: nil,
    order_by_field: nil,
    order_by_direction: nil
  )
    if !GitHub.billing_enabled?
      Licensing::BundledLicenseAssignment.none
    else
      scope = bundled_license_assignments.unassigned_user

      query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)
      scope = if query.present?
        scope.where(["email LIKE :query", { query: "%#{query}%" }])
      else
        scope
      end

      # Ignore invalid order by field and direction if provided
      order_by_field = nil unless VALID_ORDER_FIELDS_FOR_BLAS_INVITATIONS.include?(order_by_field.to_s.downcase)
      order_by_direction = nil unless VALID_DIRECTION_FIELDS.include?(order_by_direction.to_s.downcase)
      if order_by_field.present? && order_by_direction.present?
        scope = scope.order(Arel.sql("bundled_license_assignments.#{order_by_field} #{order_by_direction}"))
      end

      scope
    end
  end

  # Public: Get the pending repository invitations for any organizations that
  # are part of the business.
  #
  # NOTE: When repository invitations are bypassed and collaborators are added
  # directly to repositories in the enterprise environment, this method always
  # returns `RepositoryInvitation.none`.
  #
  # repository_visibility - Symbol restricting invitations by repository visibility.
  #                         Either :private, :public, or :all. Default: :all
  # login               - optional - String specifying user login to find. If passed only exact matches for `users.login` will be returned.
  # query:              - optional - String specifying user-provided query string.
  # order_by_field      - optional — String specifying the sort field. Supported: "created_at". Default: "created_at".
  # order_by_direction  - optional — String specifying the sort direction. Supported: "asc", "desc". Default: "desc".
  #
  # Returns an ActiveRecord::Relation
  def pending_collaborator_invitations(
    repository_visibility: :all,
    login: nil,
    query: nil,
    order_by_field: "created_at",
    order_by_direction: "desc",
    include_forks: true
  )
    return RepositoryInvitation.none if enterprise_managed_user_enabled?

    if GitHub.repo_invites_enabled?
      scope = RepositoryInvitation.for_organization_ids(organization_ids)

      scope = if repository_visibility == :private
        scope.where(repositories: { public: false, active: true })
      elsif repository_visibility == :public
        scope.where(repositories: { public: true, active: true })
      else
        scope.where(repositories: { active: true })
      end

      query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)
      scope = scope.where(repositories: { parent_id: nil }) unless include_forks

      scope = if login.present?
        user_id = User.find_by(login: login)&.id
        scope.where(invitee_id: user_id)
      elsif query.present?
        # Cater for the `users` and `repository_invitations` tables being in
        # different database clusters:
        all_invitee_ids = scope.pluck(:invitee_id)
        user_ids = User.includes(:profile).where([
          "users.id IN (:ids) AND (users.login LIKE :query OR profiles.name LIKE :query)",
          { ids: all_invitee_ids, query: "%#{query}%" }
        ]).pluck(:id)
        scope.where([
          "invitee_id IN (:user_ids) OR repository_invitations.email LIKE :query",
          { user_ids: user_ids, query: "%#{query}%" }
        ])
      else
        scope
      end

      # Ignore invalid order by field and direction
      order_by_field = "created_at" unless VALID_ORDER_FIELDS_FOR_OUTSIDE_COLAB_INVITATIONS.include?(order_by_field.to_s.downcase)
      order_by_direction = "desc" unless VALID_DIRECTION_FIELDS.include?(order_by_direction.to_s.downcase)
      scope = scope.order(Arel.sql("repository_invitations.#{order_by_field} #{order_by_direction}"))

      scope
    else
      RepositoryInvitation.none
    end
  end

  # Public: Get the business user accounts that don't have a user ID set but do have a primary
  # email from an enterprise installation.
  #
  # NOTE: When we're in a single business environment this always returns an empty array
  #
  # Returns an ActiveRecord::Relation (of `BusinessUserAccount`s)
  def user_accounts_with_only_emails
    return BusinessUserAccount.none if GitHub.single_business_environment?

    user_accounts.
      joins(:enterprise_installation_user_account_emails).
      where(user_id: nil).
      merge(EnterpriseInstallationUserAccountEmail.primary).
      distinct
  end

  # Public: Get the user IDs for all enterprise installation users that have a user associated to them.
  #
  # NOTE: When we're in a single business environment this always returns an empty array
  #
  # Returns an Array of User IDs
  def enterprise_installation_user_ids
    return [] if GitHub.single_business_environment?

    user_accounts.
      joins(:enterprise_installation_user_accounts).
      where.not(user_id: nil).
      distinct.
      pluck(:user_id)
  end

  # Public: Returns suspended members of the enterprise.
  #
  # query               - The user-provided query string
  # order_by_field      - String specifying the sort field. Supported: "login", "created_at". Default: "login".
  # order_by_direction  - String specifying the sort direction. Supported: "asc", "desc". Default: "asc".
  # viewer              - optional - the user requesting a list of suspended members
  #
  # Returns an ActiveRecord::Relation (of User type)
  def suspended_members(
    query: nil,
    order_by_field: "login",
    order_by_direction: "asc",
    viewer: nil
  )
    return unless scim_managed_enterprise?(self)

    scope = if GitHub.single_business_environment?
      User.suspended
    else
      suspended_user_scope
    end

    scope = apply_user_query_filter(scope, query, viewer: viewer)

    # Ignore invalid order by field and direction
    order_by_field = "login" unless VALID_ORDER_FIELDS_FOR_USERS.include?(order_by_field.to_s.downcase)
    order_by_direction = "asc" unless VALID_DIRECTION_FIELDS.include?(order_by_direction.to_s.downcase)
    scope.order(Arel.sql("users.#{order_by_field} #{order_by_direction}"))
  end

  # Public: Returns suspended member ids of the enterprise using batching but without any
  # support for querying or sorting, like #suspended_members
  #
  # Returns an Array of ids
  def suspended_member_ids
    return unless scim_managed_enterprise?(self)
    return User.suspended.pluck(:id) if GitHub.single_business_environment?

    emu_admin_login = User.standardize_login(self.shortcode, suffix: User::EnterpriseManagedDependency::ADMIN_SUFFIX) if self.shortcode
    business_user_ids = user_accounts.pluck(:user_id).compact

    # get the id for the first emu owner, which need to be excluded from the list
    admin_id = emu_admin_id(emu_admin_login)
    business_user_ids -= admin_id

    return [] unless business_user_ids.any?

    # No need to check if the record has been disabled by SCIM since there is no provider
    return User.batched_scope(:id, values: business_user_ids).pluck(:id) unless external_provider
    return User.where(id: business_user_ids).disabled_by_scim.where.not(login: emu_admin_login).pluck(:id) if business_user_ids.count <= USER_ACCOUNTS_THRESHOLD

    # There is an inconsistency between business user ids and the users table
    # Some of the users will still have a record in business_user_accounts table and no
    # corresponding record in the users table.
    provisioned_ids = ExternalIdentity.by_provider(external_provider)
      .pluck(:user_id, :disabled_at).to_h

    suspended_ids = provisioned_ids.select { |_id, disabled_at| disabled_at.present? }.keys

    # Missing ids are the user ids that no longer are provisioned through SCIM
    # Within the missing ids could also be users that were suspended during tenant
    # change and never re-provisioned, but they can also have users that were deleted
    # and somehow have a business_user_account record
    missing_ids = business_user_ids - provisioned_ids.keys
    return suspended_ids.compact if missing_ids.empty?

    # Since there are user ids that were not provisioned,
    # only return those that have a corresponding user record
    user_ids = User.where(id: missing_ids).pluck(:id)

    # Add queried user ids back to the business user ids
    (suspended_ids + user_ids).compact
  end

  # Public: Get the EnterpriseInstallations for a given member.
  #
  # member - A User or BusinessUserAccount to retrieve EnterpriseInstallations for.
  #
  # Returns an ActiveRecord::Relation.
  def enterprise_installations_for(member:)
    case member
    when ::BusinessUserAccount
      member.user_enterprise_installations
    when ::User
      business_user_account = self.user_accounts.find_by(user: member)
      return [] if business_user_account.blank?
      business_user_account.user_enterprise_installations
    else
      EnterpriseInstallation.none
    end
  end

  # Public: Get the Organizations within the enterprise that a given member is associated with.
  #
  # member - A User or BusinessUserAccount to retrieve Organizations for.
  # viewer - The User who is the viewer.
  #
  # Returns an ActiveRecord::Relation.
  def enterprise_organizations_for(member:, viewer:)
    case member
    when ::BusinessUserAccount
      member.enterprise_organizations(viewer)
    when ::User
      if GitHub.single_business_environment?
        member.organizations_visible_to(viewer)
      else
        business_user_account = self.user_accounts.find_by(user: member)
        return Organization.none if business_user_account.blank?
        business_user_account.enterprise_organizations(viewer)
      end
    else
      Organization.none
    end
  end

  # Public: Determines if the business can export member lists
  #
  # Returns a boolean
  def enterprise_users_export_enabled?
    !GitHub.enterprise?
  end

  # Public: User ids of users with a Copilot seat license.
  #
  # Returns an Array of Integer
  def copilot_user_ids
    return [] unless copilot_licensing_enabled?
    Copilot::SeatAssignment.for_standalone_business(T.cast(self, ::Business)).map(&:assignable).compact.flat_map(&:member_user_ids).uniq
  end

  def self.user_two_factor_statuses_argument(has_two_factor_enabled, two_factor_method_type)
    if two_factor_method_type
      case two_factor_method_type
      when "secure"
        :secure
      when "insecure"
        :insecure
      when "disabled"
        :disabled
      else
        nil
      end
    else
      case has_two_factor_enabled
      when true
        :enabled
      when false
        :disabled
      else
        nil
      end
    end
  end

  private

  def suspended_user_scope
    business_user_ids = user_accounts.pluck(:user_id).compact
    emu_admin_login = User.standardize_login(self.shortcode, suffix: User::EnterpriseManagedDependency::ADMIN_SUFFIX) if self.shortcode

    # no need to check disabled_by_scim, since there is no provider
    return User.where(id: business_user_ids).where.not(login: emu_admin_login) unless external_provider

    # since this is a faster query then doing calculations in, but fails when too many users ids are passed
    # into the where statement, we need to check the number of users ids before running the query and fall back
    # to calculating the suspended users in multiple queries
    return User.where(id: business_user_ids).disabled_by_scim.where.not(login: emu_admin_login) if business_user_ids.count <= USER_ACCOUNTS_THRESHOLD

    admin_id = emu_admin_id(emu_admin_login)

    # The goal for this query is to remove the large list of suspended users added to a where statement
    # This query will be slower for customer that do not have a large number of suspended users

    # There is an inconsistency between business user ids and the users table
    # Some of the users will still have a record in business_user_accounts table and no
    # corresponding record in the users table.
    provisioned_ids = ExternalIdentity.by_provider(external_provider).pluck(:user_id)
    missing_ids = (business_user_ids - provisioned_ids - admin_id).flatten

    suspended = User.joins(:external_identities)
      .where(external_identities: { provider: external_provider })
      .where.not(external_identities: { disabled_at: nil })

    if missing_ids.any?
      missing_scope = User.where(id: missing_ids)
      User.from("(#{suspended.to_sql} UNION ALL #{missing_scope.to_sql}) AS users")
    else
      suspended
    end
  end

  def emu_admin_id(emu_admin_login)
    admin_id = if GitHub.multi_tenant_enterprise?
      # Unscope for query for the first admin user.
      # Since creation is performed outside the context of a tenant
      # so we shouldn't scope to the tenant during this query.
      GitHub::CurrentTenant.unscope do
        User.where(login: emu_admin_login).pluck(:id)
      end
    else
      User.where(login: emu_admin_login).pluck(:id)
    end
  end

  def apply_login_filter(scope, login)
    return scope if login.blank?

    scope.where(["users.login = :login", { login: login }])
  end

  # Private: filter the values in the given scope by the specified query string. Return only
  # the users whose login or name includes the specified string. Return the given scope if
  # query parameter is nil.
  #
  # scope  - scope of Business users or administrators
  # query  - filter query string
  # viewer - the user requesting the user query results
  #
  # Returns an ActiveRecord::Relation for the business' users with the given filter applied
  def apply_user_query_filter(scope, query, viewer: nil)
    query_for_equals = query.to_s.strip.downcase
    return scope unless query_for_equals.present?
    query_for_like = ActiveRecord::Base.sanitize_sql_like(query_for_equals)
    actor_can_read_members = actor_can_read_members?(viewer)

    if scope.table_name == "business_user_accounts"
      email_query = ""
      if viewer && (actor_can_read_members || viewer.site_admin?) && query_for_equals.match(User::EMAIL_REGEX)
        email_query = " OR business_user_accounts.verified_emails LIKE :query"
      end
      scope.joins("LEFT JOIN enterprise_installation_user_accounts ON enterprise_installation_user_accounts.business_user_account_id = business_user_accounts.id")
        .where(["business_user_accounts.login LIKE :query OR business_user_accounts.profile_name LIKE :query OR enterprise_installation_user_accounts.profile_name LIKE :query#{email_query}", { query: "%#{query_for_like}%" }])
    else
      if viewer && (actor_can_read_members || viewer.site_admin?) && query_for_equals.match(User::EMAIL_REGEX)
        return scope.includes(:emails).includes(external_identities: :identity_attribute_records)
          .where(<<-SQL, query: "%#{query_for_like}%", email: query_for_equals, verified: "verified", name_id: "NameID", emails: "emails")
            users.login LIKE :query OR
            ( user_emails.state = :verified AND user_emails.email = :email ) OR
            (
              ( external_identity_attributes.name = :name_id OR external_identity_attributes.name = :emails) AND
              external_identity_attributes.value = :email
            )
          SQL
        .references(:user_emails, :identity_attribute_records)
      end

      scope.includes(:profile)
        .where(["users.login LIKE :query OR profiles.name LIKE :query", { query: "%#{query_for_like}%" }])
        .references(:profile)
    end
  end

  # Private: filter the scope to only include users in the given organization.
  def filter_by_organization(scope, org_ids)
    return scope if org_ids.blank?
    scope.where(id: organization_member_ids(org_ids: org_ids))
  end

  # Private: Filter an existing scope to only include users with given 2FA status.
  #
  # scope - ActiveRecord::Relation to apply filtering to.
  # status - Symbol which can be either :enabled, :required, :secure, :insecure, or :disabled. Other values will
  #   be ignored and return the existing scope.
  #
  # Returns ActiveRecord::Relation.
  def filter_users_by_two_factor_status(scope, status)
    if status == :enabled
      scope = scope.two_factor_enabled
    elsif status == :required
      scope = scope.with_account_two_factor_requirement
    elsif status == :secure
      scope = scope.two_factor_enabled.without_insecure_two_factor_methods
    elsif status == :insecure && GitHub.two_factor_sms_enabled?
      scope = scope.two_factor_enabled.with_insecure_two_factor_methods
    elsif status == :disabled
      scope = scope.two_factor_disabled
    end

    scope
  end

  # Private: Filter an existing BUA scope to only include users with given 2FA status.
  #
  # scope - ActiveRecord::Relation to apply filtering to.
  # status - Symbol which can be either :enabled, :required or :disabled. Other values will
  #   be ignored and return the existing scope.
  #
  # Returns ActiveRecord::Relation.
  def filter_user_accounts_by_two_factor_status(scope, status)
    if [:enabled, :required, :disabled].include?(status)
      return scope.where(two_factor_status: status)
    end
    scope
  end

  # Private: Filter the scope to only include users with a given cost center
  #
  # cost_center - String representing the cost center to filter by. If nil
  # will return all users. If "no-cost-center" will return all users with no cost center.
  sig { params(scope: ActiveRecord::Relation, cost_center: T.nilable(String)).returns(ActiveRecord::Relation) }
  def filter_by_cost_center(scope, cost_center)
    return scope if cost_center.blank? || self.cost_centers.nil?
    cost_center_ids = user_ids_for_cost_center(cost_center)

    if cost_center == FILTER_VALUE_NO_COST_CENTER
      scope.where.not(user_id: cost_center_ids).or(scope.where(user_id: nil))
    else
      scope.where(user_id: cost_center_ids)
    end
  end

  # Private: Filter BusinessUserAccount scope to only include users with a given cost center
  #
  # cost_center - String representing the cost center to filter by. If nil
  # will return all users. If "no-cost-center" will return all users with no cost center.
  sig { params(scope: ActiveRecord::Relation, cost_center: String).returns(ActiveRecord::Relation) }
  def filter_user_accounts_by_cost_center(scope, cost_center)
    if cost_center.nil?
      scope
    elsif cost_center == FILTER_VALUE_NO_COST_CENTER
      scope.where(cost_center: nil)
    else
      cost_center_uuids = cost_centers&.select { |c| c.dig(:name)&.parameterize == cost_center }&.compact&.map { |c| c.dig(:costCenterKey, :uuid) }&.compact&.first || cost_center
      scope.where(cost_center: cost_center_uuids)
    end
  end

  # Private: Retrieves user ids who belong to a given cost center. Returns all user ids found if given
  # cost center "no-cost-center"
  sig { params(filter_cost_center: String).returns(T::Array[Integer]) }
  def user_ids_for_cost_center(filter_cost_center)
    user_ids = []
    self.cost_centers&.each do |cost_center|
      next unless cost_center.dig(:name)&.parameterize == filter_cost_center || cost_center.dig(:costCenterKey, :uuid) == filter_cost_center || filter_cost_center == FILTER_VALUE_NO_COST_CENTER
      cost_center.dig(:resources)&.each do |resource|
        next unless resource.dig(:type) == :User
        user_ids.push(resource.dig(:id).to_i)
      end
    end

    user_ids
  end

  # Private: Retrieve the administrators of this business who have the specified role.
  #
  # role - Only return admins with the given role. Valid values: [:owner, :billing_manager]
  #        A nil role will return all administrators.
  #        Invalid roles will be ignored and treated as nil.
  #
  # Returns an ActiveRecord::Relation for the business' administrators
  def admins_with_role(role)
    case role&.to_sym
    when Business::OWNER_ROLE
      owners
    when Business::BILLING_MANAGER_ROLE
      billing_managers
    else
      query = owners.or(billing_managers)
      query
    end
  end

  # Private: retrieves Organization ids whose login matches values in `org_logins`
  #
  # Returns an Array of Integer database ids if `org_logins` passed, otherwise nil
  def org_database_ids(org_logins)
    return unless org_logins.present?
    organizations.where(login: org_logins).limit(100).pluck(:id)
  end

  # Private: builds a scope based on BusinessUserAccounts that allows filtering by the
  # * org_member_type (:admin, :member_without_admin, or :all)
  # * deployment (NONE, CLOUD, or SERVER)
  # * organization_ids
  #
  # When organization_ids are passed we're not able to query for users since we don't have
  # any organization name information from GHES to filter by. See inline comments, if you dare, for a deeper
  # explanations of quirks, reasonings, etc.
  #
  # Returns an ActiveRecord::Relation
  def enterprise_user_scope(query, org_member_type, organization_ids, two_factor)
    scope = BusinessUserAccount
      .left_joins(:enterprise_installation_user_accounts)
      .where(business_id: id)

    # We currently can't filter server users by organization. Nothing to do here if there are org ids passed.
    # Return a scope for the UNION query that will effectively result in [] but is structurally compatible so
    # that Arel will do assemble the SQL for us
    return scope.none if organization_ids&.any?

    # We currently can't filter server users by lack of organization either.
    return scope.none if [:unaffiliated, :guest_collaborator].include?(org_member_type)

    # Can't filter by 2FA status for server users; this would slow filtered_members considerably as would require
    # filtering each BUA manually.
    return scope.none if [:disabled, :required, :enabled, :secure, :insecure].include?(two_factor)

    # filters out BusinessUserAccounts with no enterprise_installation_user_account for the Business
    scope = scope.where.not(enterprise_installation_user_accounts: { id: nil })

    query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)
    return scope if query.nil? && org_member_type == :all

    # enterprise_installation_user_accounts.site_admin (Boolean) can be used to filter by Role. possible query values/explanations:
    #   true: user is a site admin on a GHE Server installation but is listed alongside Cloud _members_. they're analogous to Cloud Organization owner/admins.
    #   false: user is a member of a GHE Server installation and is analogous to a Cloud Organization member
    #   if we are filtering by business admin roles we don't need to filter by site admin as all filtering is done previously
    if org_member_type != :all && !Business::ADMIN_ROLES.include?(org_member_type)
      scope = scope.where(enterprise_installation_user_accounts: { site_admin: (org_member_type == :admin) })
    end

    if query.present?
      scope = scope.where(["business_user_accounts.login LIKE :query OR enterprise_installation_user_accounts.profile_name LIKE :query", { query: "%#{query}%" }])
    end

    scope
  end

  # Private: for GHEC with a valid VSS bundled license present this will return a new ActiveRecord::Relation which filters
  #   by license type (:vss_bundle or :enterprise)
  #
  # Returns an ActiveRecord::Relation
  def filter_by_license(scope, license, bua_filtered_members: false)
    if bua_filtered_members && !license.blank?
      scope = scope.exclusive_no_roles(:billing_manager)
    end

    return scope if GitHub.single_business_environment? || license.blank? || (!volume_licensing_enabled? && license.to_sym != :copilot && license.to_sym != :no_copilot)

    case license.to_sym
    when :enterprise
      without_vss_users = scope.without_ids(volume_licensed_user_ids, field: :user_id)
      if scope.values.dig(:left_outer_joins)&.include?(:enterprise_installation_user_accounts) || bua_filtered_members
        # If our scope is joining to enterprise installations, we want to include server users
        # that don't have a linked GitHub account, so we need the query to include user_accounts
        # without a user_id or use_acounts excluding vss user ids
        without_vss_users.or(scope.where(user_id: nil))
      else
        # If our scope is filtering to only cloud users either explictly or implicitly via an attribute
        # that only applies to cloud users, the scope won't have the enterprise_installation_user_accounts join
        # and we don't want to include nil user_ids in the query
        without_vss_users
      end
    when :copilot
      scope.where(user_id: copilot_user_ids)
    when :no_copilot
      scope.where.not(user_id: copilot_user_ids)
    when :vss_bundle
      scope.where(user_id: volume_licensed_user_ids)
    end
  end

  # Private: Determines if the filter criteria for members would result in empty search results
  #
  # Returns a boolean
  def incompatible_filter_criteria?(options)
    return true if options[:organization_ids].blank? && options[:organization_logins].present?
    return true if (options[:org_member_type] == :unaffiliated) && options[:organization_logins].present?
    false
  end

  # Private: User ids of users with a volume license.
  #
  # Returns an Array of Integer
  def volume_licensed_user_ids
    bundled_license_assignments.assigned_user.pluck(:user_id)
  end

  # Private: Determines if the viewer is allowed to use the provided filter criteria
  #
  # Returns a boolean
  def is_allowed_to_use_filters?(viewer, options)
    return true if actor_can_read_members?(viewer) || viewer&.site_admin? || options[:allow_filters_for_non_admin_viewer]
    return false if ![:all, :owner].include?(options[:org_member_type])
    return false if options[:organization_ids].present? || options[:organization_logins].present?
    return false if options[:deployment].present? || options[:license].present? || options[:two_factor].present?
    true
  end

  # Private: builds a Users scope matching the provided filters & search query
  #
  # Returns an ActiveRecord::Relation
  def build_user_scope(viewer, options, batched_ids: false, batch_size: nil, skip_emu_admin: false)
    # For EMU with no other filters, get all User accounts with a matching External Identity account by provider
    if enterprise_managed_user_enabled? && [:all, :unaffiliated, :guest_collaborator].include?(options[:org_member_type]) && options[:organization_ids].blank?
      users_scope = if self.external_provider.present?
        User.joins(:external_identities).
          where(external_identities: { provider_id: self.external_provider.id, provider_type: self.external_provider.class.name, disabled_at: nil })
      else
        User.none
      end

      if options[:org_member_type] == :guest_collaborator
        users_scope = users_scope.where(external_identities: { guest_collaborator: true })
      elsif !skip_emu_admin
        emu_admin_login = User.standardize_login(self.shortcode, suffix: User::EnterpriseManagedDependency::ADMIN_SUFFIX)
        emu_admin_scope = User.where(login: emu_admin_login)
        if !options[:license].blank? || options[:org_member_type] == :unaffiliated
          users_scope = User.from("(#{users_scope.to_sql} UNION #{emu_admin_scope.to_sql}) AS users")
          emu_admin_scope = nil
        end
        if !actor_can_read_members?(viewer) && !viewer&.site_admin?
          emu_admin_scope = nil
        end
      end

      if options[:org_member_type] == :unaffiliated
        # Business owners/billing managers should be excluded from the unaffiliated emus list
        all_org_member_ids = visible_organization_members_for(viewer,
                                type: :all,
                                ignore_visibility: true,
                                org_ids: self.organizations.ids
                              ).ids
        affiliated_business_members = (all_org_member_ids + admins.ids).uniq
        users_scope = users_scope.where.not(id: affiliated_business_members)
      end
    else
      # User scope is based on what members the viewer can see, given filter options
      # For EMU, users are provisioned at the business level and every user in the EMU enterprise should be able to
      # see all users provisioned. So we override ignore_visibility for EMU.
      # If we are filtering by admin type we get all users and apply filters in the admin_scope_builder
      users_scope = visible_organization_members_for(
        viewer,
        type: Business::ADMIN_ROLES.include?(options[:org_member_type]) ? :all : options[:org_member_type],
        ignore_visibility: enterprise_managed_user_enabled? ? true : options[:ignore_org_membership_visibility],
        org_ids: options[:organization_ids],
      )

      if options[:org_member_type] == :guest_collaborator
        users_scope = users_scope.joins(:external_identities).
          where(external_identities: { provider_id: self.external_provider.id, provider_type: self.external_provider.class.name, guest_collaborator: true })
      end
    end

    if include_admins?(viewer, options)
      users_scope = admins_scope_builder(users_scope, options)
    end

    if emu_admin_scope
      users_scope = User.from("(#{users_scope.to_sql} UNION #{emu_admin_scope.to_sql}) AS users")
    end

    users_scope = apply_user_query_filter(users_scope, options[:query], viewer: viewer)
    unless actor_can_read_members?(viewer) || enterprise_managed_user_enabled?
      users_scope = users_scope.filter_spam_for(viewer)
    end

    unless enterprise_managed_user_enabled?
      users_scope = filter_users_by_two_factor_status(users_scope, options[:two_factor])
    end

    if include_account_type?(options)
      users_scope = account_type_scope_builder(users_scope, options)
    end

    users_scope.distinct
  end

  # Private: Determines if we need to include admins in the user scope
  #
  # Returns a boolean
  def include_admins?(viewer, options)
    (actor_can_read_members?(viewer) || seats_plan_basic?) &&
    (options[:org_member_type] == :all || Business::ADMIN_ROLES.include?(options[:org_member_type]))
  end

  def include_account_type?(options)
    return false unless GitHub.single_business_environment? && GitHub.auth.saml?
    [:built_in, :saml_linked, :saml_and_scim_linked].include?(options[:account_type])
  end

  # Private: applies filters for business admins to the users scope.
  # We need to pass in the options hash because how we filter depends on whether we are filtering on multiple fields
  #
  # Returns an ActiveRecord::Relation
  def admins_scope_builder(users_scope, options)
    if Business::ADMIN_ROLES.include?(options[:org_member_type])
      # If we are filtering by license or org_ids the users have already been included the scope from visible_organization_members_for
      # and we need to narrow the scope to admins only. Otherwise we can replace the scope with the admins scope.
      if options[:license].present? || options[:organization_ids].present?
        users_scope = users_scope.where(id: admins_with_role(options[:org_member_type]).pluck(:id))
      else
        users_scope = admins_with_role(options[:org_member_type])
      end
    # If we aren't filtering by admin roles or license/org ids we include all the admins into the scope to get users who
    # haven't been included included in visible_organization_members (ie business admins who are not organization members/owners).
    # If we are filtering by license or org_ids they will already be included from visible_organization_members_for
    elsif options[:license].blank? && options[:organization_ids].blank?
      users_scope = users_scope.or(admins_with_role(nil))
    end
    users_scope
  end

  # Private: applies filters for account types to the users scope.
  #
  # Returns an ActiveRecord::Relation
  def account_type_scope_builder(users_scope, options)
    return users_scope unless GitHub.single_business_environment?

    case options[:account_type]
    when :built_in
      users_scope
        .left_joins(:external_identities).where(external_identities: { user_id: nil })
        .left_joins(:saml_mapping).where(saml_mapping: { user_id: nil })
    when :saml_linked
      users_scope
        .left_joins(:external_identities).where(external_identities: { user_id: nil })
        .joins(:saml_mapping)
    when :saml_and_scim_linked
      users_scope.joins(:external_identities)
    else
      users_scope
    end
  end

  # Private: builds a BusinessUserAccounts scope based on a Users Accounts scope
  #
  # Returns an ActiveRecord::Relation
  def build_business_user_scope(users_scope, options)
    case options[:deployment]
    when nil
      # If we are filtering by an admin role we don't need to get accounts that are only on server installations
      if Business::ADMIN_ROLES.include?(options[:org_member_type])
        business_user_account_scope = BusinessUserAccount.where(user_id: users_scope.pluck(:id))
      else
        # All accounts: business user accounts matching users_scope, UNION filtered business user accounts from Servers
        cloud_user_accounts = if options[:org_member_type] == :unaffiliated && !enterprise_managed_user_enabled?
          BusinessUserAccount \
            .where(business_id: id)
            .left_joins(:enterprise_installation_user_accounts)
            .preload(user: :profile)
            .exclusive_unaffiliated_role
        else
          BusinessUserAccount \
            .where(business_id: id)
            .left_joins(:enterprise_installation_user_accounts)
            .where(user_id: users_scope.pluck(:id))
            .preload(user: :profile)
        end

        server_user_accounts = enterprise_user_scope(
          options[:query],
          options[:org_member_type],
          options[:organization_ids],
          options[:two_factor])

        business_user_account_scope = cloud_user_accounts.or(server_user_accounts).distinct
      end
    when "cloud"
      # business user accounts matching users_scope
      business_user_account_scope = if options[:org_member_type] == :unaffiliated && !enterprise_managed_user_enabled?
        BusinessUserAccount.where(business_id: id).exclusive_unaffiliated_role
      else
        BusinessUserAccount.where(user_id: users_scope.pluck(:id))
      end
    when "server"
      # filtered business user accounts from Servers
      business_user_account_scope = enterprise_user_scope(
        options[:query],
        options[:org_member_type],
        options[:organization_ids],
        options[:two_factor]).distinct
      if Business::ADMIN_ROLES.include?(options[:org_member_type])
        business_user_account_scope = business_user_account_scope.where(user_id: users_scope.pluck(:id))
      end
    end

    business_user_account_scope = filter_by_cost_center(business_user_account_scope, options[:cost_center])
    business_user_account_scope = filter_by_license(business_user_account_scope, options[:license])
    business_user_account_scope.where(business_id: id)
  end

  # Private: builds a BusinessUserAccounts scope based on a Users Accounts scope
  #
  # Returns an ActiveRecord::Relation
  def build_business_user_batched_scope(user_ids, options, order_by_field, order_by_direction, batch_size)
    order = "business_user_accounts.#{order_by_field} #{order_by_direction}"

    if options[:cost_center].present? && !self.cost_centers.nil?
      cost_center_user_ids = user_ids_for_cost_center(options[:cost_center])
      if options[:cost_center] == FILTER_VALUE_NO_COST_CENTER
        user_ids = user_ids - cost_center_user_ids
      else
        return BusinessUserAccount.none if cost_center_user_ids.empty?
        user_ids = user_ids & cost_center_user_ids
      end
    end

    # If we are filtering by an admin role we don't need to get accounts that are only on server installations
    scope = case options[:deployment]
    when nil
      if Business::ADMIN_ROLES.include?(options[:org_member_type])
        BusinessUserAccount.batched_scope(:user_id, values: user_ids, batch_size: batch_size) do |sc|
          sc = filter_by_license(sc, options[:license])
          sc.where(business_id: id)
        end
      else
        # All accounts: business user accounts matching user_ids, UNION filtered business user accounts from Servers
        if user_ids.any?
          server_user_account_scope = enterprise_user_scope(
            options[:query],
            options[:org_member_type],
            options[:organization_ids],
            options[:two_factor]
          )
          server_user_account_scope = filter_by_license(server_user_account_scope, options[:license])
          server_user_account_scope = filter_by_cost_center(server_user_account_scope, options[:cost_center])
          server_user_account_ids = server_user_account_scope.pluck(:id)

          business_ids = T.unsafe(BusinessUserAccount.where(business_id: id)).batched_scope(:user_id, values: user_ids, batch_size: batch_size).pluck(:id)
          server_ids = filter_by_license(BusinessUserAccount.left_joins(:enterprise_installation_user_accounts).where(business_id: id), options[:license]).pluck(:id)

          BusinessUserAccount.batched_scope(:id, values: ((server_ids & business_ids) + server_user_account_ids).uniq, batch_size: batch_size)
        else
          cloud_user_accounts = BusinessUserAccount.
            left_joins(:enterprise_installation_user_accounts).
            where(user_id: user_ids)
          server_user_accounts = enterprise_user_scope(
            options[:query],
            options[:org_member_type],
            options[:organization_ids],
            options[:two_factor])

          business_user_account_scope = cloud_user_accounts.or(server_user_accounts).distinct
          business_user_account_scope = filter_by_license(business_user_account_scope, options[:license])
          business_user_account_scope.where(business_id: id)
        end
      end
    when "cloud"
      BusinessUserAccount.batched_scope(:user_id, values: user_ids, batch_size: batch_size) do |sc|
        sc = filter_by_license(sc, options[:license])
        sc.where(business_id: id)
      end
    when "server"
      # filtered business user accounts from Servers
      if user_ids.any? && Business::ADMIN_ROLES.include?(options[:org_member_type])
        enterprise_user_batched_scope(
          options[:query],
          options[:org_member_type],
          options[:organization_ids],
          options[:two_factor],
          options[:license],
          user_ids,
          batch_size)
      elsif cost_center_user_ids.present? && options[:cost_center] != FILTER_VALUE_NO_COST_CENTER
        enterprise_user_batched_scope(
          options[:query],
          options[:org_member_type],
          options[:organization_ids],
          options[:two_factor],
          options[:license],
          cost_center_user_ids,
          batch_size)
      else
        filter_by_cost_center(enterprise_user_scope(
          options[:query],
          options[:org_member_type],
          options[:organization_ids],
          options[:two_factor]), options[:cost_center]).distinct
      end
    end

    scope.order(Arel.sql(order))
  end

  def enterprise_user_batched_scope(query, org_member_type, organization_ids, two_factor, license, user_ids, batch_size)
    # We currently can't filter server users by organization. Nothing to do here if there are org ids passed.
    # Return a scope for the UNION query that will effectively result in [] but is structurally compatible so
    # that Arel will do assemble the SQL for us
    return BusinessUserAccount.none if organization_ids&.any?

    # We currently can't filter server users by lack of organization either.
    return BusinessUserAccount.none if [:unaffiliated, :guest_collaborator].include?(org_member_type)

    # Can't filter by 2FA status for server users; this would slow filtered_members considerably as would require
    # filtering each BUA manually.
    return BusinessUserAccount.none if [:disabled, :required, :enabled, :secure, :insecure].include?(two_factor)

    query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)

    BusinessUserAccount.batched_scope(:user_id, values: user_ids, batch_size: batch_size) do |sc|
      sc = sc.left_joins(:enterprise_installation_user_accounts)
      sc = sc.where.not(enterprise_installation_user_accounts: { id: nil })

      unless query.nil? || org_member_type == :all
        # enterprise_installation_user_accounts.site_admin (Boolean) can be used to filter by Role. possible query values/explanations:
        #   true: user is a site admin on a GHE Server installation but is listed alongside Cloud _members_. they're analogous to Cloud Organization owner/admins.
        #   false: user is a member of a GHE Server installation and is analogous to a Cloud Organization member
        #   if we are filtering by business admin roles we don't need to filter by site admin as all filtering is done previously
        if org_member_type != :all && !Business::ADMIN_ROLES.include?(org_member_type)
          sc = sc.where(enterprise_installation_user_accounts: { site_admin: (org_member_type == :admin) })
        end

        if query.present?
          sc = sc.where(["business_user_accounts.login LIKE :query OR enterprise_installation_user_accounts.profile_name LIKE :query", { query: "%#{query}%" }])
        end
      end

      sc = filter_by_license(sc, license)
      sc.where(business_id: id)
    end
  end
end
