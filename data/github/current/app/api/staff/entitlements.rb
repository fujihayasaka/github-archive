# typed: true
# frozen_string_literal: true

class Api::Staff::Entitlements < Api::Staff::App
  unless GitHub.enterprise?
    PROTECTED_ROLE = "entitlements_master"
    # API's for granting access to stafftools and the staff api
    # Docs https://github.com/github/githubber-content/blob/master/docs/technology/dotcom/stafftools/api/entitlements.md

    # Retrieve all users with stafftools access
    get "/staff/stafftools/accesses", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
      @route_owner = "@github/stafftools"
      deliver :stafftools_accesses,
        paginate_rel(::User.includes(:stafftools_roles).where(gh_role: "staff"))
    end

    # Update list of users with stafftools access
    put "/staff/stafftools/accesses", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
      @route_owner = "@github/stafftools"
      data = attr(receive(Hash), :users)

      queue_attempt = AssignStafftoolsAccessJob.attempt_to_enqueue(data[:users])

      if queue_attempt.has_key?(:errors)
        deliver_error! 422, {
          message: "Cannot assign stafftools access to users: #{queue_attempt[:errors].join(", ")}",
        }
      end

      results = queue_attempt
      deliver :stafftools_accesses_job, results, status: 202
    end

    # Update a single user to have stafftools access
    put "/staff/stafftools/accesses/:username", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
      @route_owner = "@github/stafftools"
      user = fetch_user(params[:username])
      if user.can_become_staff?
        AssignStafftoolsAccessJob.grant_stafftools_access(user)
      else
        # API is only used as internal by staff therefore safe to use login here.
        deliver_error! 422, { message: "Cannot assign stafftools access to user: #{user.login}" } # rubocop:disable GitHub/DoNotAllowLogin
      end

      # API is only used as internal by staff therefore safe to use login here.
      deliver :stafftools_accesses, fetch_user(user.login) # rubocop:disable GitHub/DoNotAllowLogin
    end

    # Remove a single user from stafftools access
    delete "/staff/stafftools/accesses/:username", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
      @route_owner = "@github/stafftools"
      deliver_error! 404 if params[:username] == "thechickeneater"
      user = fetch_user(params[:username])
      AssignStafftoolsAccessJob.revoke_stafftools_access(user)
      deliver_empty(status: 204)
    end

    # Get all available stafftools roles
    get "/staff/stafftools/roles", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
      @route_owner = "@github/stafftools"
      deliver :stafftools_role, ::StafftoolsRole.all
    end

    # Get all users assigned to a specific stafftools role
    get "/staff/stafftools/roles/:rolename/accesses", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
      @route_owner = "@github/stafftools"
      deliver_error! 404 if params[:rolename] == PROTECTED_ROLE
      role_id = T.must(::StafftoolsRole.find_by(name: params[:rolename])).id

      users = User.includes(:stafftools_roles).
        where(id: UserStafftoolsRole.where(stafftools_role_id: role_id).pluck(:user_id))
      deliver :stafftools_accesses, users
    end

    # Update users assigned to a stafftools role
    put "/staff/stafftools/roles/:rolename/accesses", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
      @route_owner = "@github/stafftools"
      deliver_error! 404 if params[:rolename] == PROTECTED_ROLE
      role = ::StafftoolsRole.find_by(name: params[:rolename])

      data = attr(receive(Hash), :users)

      attempt_to_assign = AssignStafftoolsRoleJob.attempt_to_queue(data["users"], role)

      if attempt_to_assign.has_key?(:errors)
        deliver_error! 422, {
          message: "Cannot assign #{T.must(role).name} to users: #{attempt_to_assign[:errors].join(", ")}" }
      end

      results = attempt_to_assign
      deliver :stafftools_accesses_job, results, status: 202
    end

    # Give a stafftools role to a single user
    # rubocop:todo GitHub/ControlAccess
    put "/staff/stafftools/roles/:rolename/accesses/:username", operation_id: :internal do
      @route_owner = "@github/stafftools"
      deliver_error! 404 if params[:rolename] == PROTECTED_ROLE

      user = User.find_by_login(params[:username])
      role = ::StafftoolsRole.find_by(name: params[:rolename])
      begin
        AssignStafftoolsRoleJob.assign_stafftools_role(user, role)
      rescue ActiveRecord::RecordInvalid => e
        deliver_error! 422, { message: e.message, errors: { resource: e.record.class.name } }
      end

      deliver :stafftools_role, user.reload.stafftools_roles
    end
    # rubocop:enable GitHub/ControlAccess

    # remove a stafftools roles from a single user
    # rubocop:todo GitHub/ControlAccess
    delete "/staff/stafftools/roles/:rolename/accesses/:username", operation_id: :internal do
      @route_owner = "@github/stafftools"
      deliver_error! 404 if params[:rolename] == PROTECTED_ROLE

      user = User.find_by_login(params[:username])
      role = ::StafftoolsRole.find_by(name: params[:rolename])

      AssignStafftoolsRoleJob.revoke_stafftools_role(user, role)
      deliver_empty(status: 204)
    end
    # rubocop:enable GitHub/ControlAccess

    private

    def fetch_user(login)
      User.includes(:stafftools_roles).find_by(login: login)
    end
  end
end
