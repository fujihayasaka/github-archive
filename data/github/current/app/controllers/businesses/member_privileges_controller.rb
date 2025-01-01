# typed: true
# frozen_string_literal: true

class Businesses::MemberPrivilegesController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :update_protected_branches_setting_flag_required, only: [:update_members_can_update_protected_branches]
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required

  include ApplicationHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:index]

  def index
    view = create_view_model(
      Businesses::Settings::MemberPrivilegesView,
      business: this_business,
      params: params
    )
    render "businesses/settings/member_privileges", locals: { view: view }
  end

  def update_members_can_delete_issues # rubocop:todo GitHub/UseRestfulActions
    setting_value = members_can_delete_issues_params[:members_can_delete_issues]
    validate_setting value: setting_value

    message = ""
    case setting_value
    when "enabled"
      this_business.allow_members_can_delete_issues(actor: current_user, force: true)
      message = "Members can now delete issues."
    when "disabled"
      this_business.disallow_members_can_delete_issues(actor: current_user, force: true)
      message = "Members can no longer delete issues."
    when "no_policy"
      this_business.clear_members_can_delete_issues(actor: current_user)
      message = "Organization administrators can now change this setting for individual organizations."
    end

    redirect_to :back, notice: message
  end

  def update_members_can_update_protected_branches # rubocop:todo GitHub/UseRestfulActions
    setting_value = members_can_update_protected_branches_params[:members_can_update_protected_branches]
    validate_setting value: setting_value

    message = ""
    case setting_value
    when "enabled"
      this_business.allow_members_can_update_protected_branches(actor: current_user, force: true)
      message = "Members can now update protected branches."
    when "disabled"
      this_business.disallow_members_can_update_protected_branches(actor: current_user, force: true)
      message = "Members can no longer update protected branches."
    when "no_policy"
      this_business.clear_members_can_update_protected_branches(actor: current_user)
      message = "Organization administrators can now change this setting for individual organizations."
    end

    redirect_to :back, notice: message
  end

  def update_members_can_delete_repositories # rubocop:todo GitHub/UseRestfulActions
    setting_value = members_can_delete_repos_params[:members_can_delete_repositories]
    validate_setting value: setting_value

    message = ""
    case setting_value
    when "enabled"
      this_business.allow_members_can_delete_repositories(actor: current_user, force: true)
      message = "Members can now delete or transfer repositories."
    when "disabled"
      this_business.disallow_members_can_delete_repositories(actor: current_user, force: true)
      message = "Members can no longer delete or transfer repositories."
    when "no_policy"
      this_business.clear_members_can_delete_repositories(actor: current_user)
      message = "Organization administrators can now change this setting for individual organizations."
    end

    redirect_to :back, notice: message
  end

  NO_POLICY_VALUE = "no_policy"
  DISABLED_VALUE = "disabled"
  ALLOWED_VALUE = "allowed"
  ALL_VALUES = [NO_POLICY_VALUE, DISABLED_VALUE, ALLOWED_VALUE].freeze

  def update_members_can_create_repositories # rubocop:todo GitHub/UseRestfulActions
    members_can_create_repositories = members_can_create_repos_params[:members_can_create_repositories]
    validate_setting value: members_can_create_repositories, valid_values: ALL_VALUES

    enabled_visibilities = case members_can_create_repositories
    when NO_POLICY_VALUE
      this_business.clear_members_can_create_repositories(actor: current_user)
    when DISABLED_VALUE
      this_business.allow_members_can_create_repositories_with_visibilities(
        force: true,
        actor: current_user,
        public_visibility: false,
        private_visibility: false,
        internal_visibility: false,
      )
    when ALLOWED_VALUE
      this_business.allow_members_can_create_repositories_with_visibilities(
        force: true,
        actor: current_user,
        public_visibility: members_can_create_repos_params[:public] == "true",
        private_visibility: members_can_create_repos_params[:private] == "true",
        internal_visibility: members_can_create_repos_params[:internal] == "true",
      )
    end

    message = if enabled_visibilities.nil?
      "Organization administrators can now change this setting for individual organizations."
    elsif enabled_visibilities.present?
      "Members can now create #{to_sentence(enabled_visibilities)} repositories."
    else
      "Members can no longer create repositories."
    end

    redirect_to :back, notice: message
  end

  def update_restrict_create_repository_in_personal_namespace # rubocop:todo GitHub/UseRestfulActions
    if %w[0 1].include?(params[:restrict_create_repository_in_personal_namespace])
      message = if params[:restrict_create_repository_in_personal_namespace] == "1"
        this_business.enable_restrict_create_repository_in_personal_namespace(actor: current_user)
        "Users can no longer create repositories in their personal namespace inside this enterprise."
      else
        this_business.disable_restrict_create_repository_in_personal_namespace(actor: current_user)
        "Users can now create repositories in their personal namespace inside this enterprise."
      end
    end

    redirect_to settings_member_privileges_enterprise_path(this_business), notice: message
  end

  def update_default_branch_setting # rubocop:todo GitHub/UseRestfulActions
    enforce = params[:default_branch_enforce] == "1"
    raw_name = params[:default_branch_name]
    is_enforce_changing = enforce != this_business.custom_default_new_repo_branch_enforced?

    if raw_name.blank?
      flash[:error] = "Could not update default branch name preference, " \
        "no branch name given."
    else
      normalized_name = Git::Ref.normalize(raw_name)
      is_name_changing = normalized_name != this_business.custom_default_new_repo_branch

      if normalized_name.blank?
        flash[:error] = "Could not update default branch name preference, " \
          "'#{raw_name}' is not a valid branch name."
      elsif !is_name_changing && !is_enforce_changing
        flash[:notice] = "#{this_business}'s default branch name is already #{normalized_name}."
      elsif this_business.set_default_new_repo_branch(normalized_name, actor: current_user, enforce: enforce)
        flash[:notice] = if is_name_changing
          "New repositories created in #{this_business} will use " \
          "#{normalized_name} as their default branch. Organizations will#{' not' if enforce} " \
          "be able to override this."
        elsif enforce
          "#{this_business}'s default branch name of #{normalized_name} is now enforced."
        else
          "#{this_business}'s default branch name of #{normalized_name} is no longer enforced."
        end
      else
        flash[:error] = "Could not set the default branch name preference for " \
          "#{this_business} at this time."
      end
    end

    redirect_to settings_member_privileges_enterprise_path(this_business)
  end

  def update_members_can_invite_outside_collaborators # rubocop:todo GitHub/UseRestfulActions
    return render_404 if this_business.enterprise_managed_user_enabled? && !this_business.emu_repository_collaborators_policy_enabled?

    setting_value = members_can_invite_outside_collaborators_params[:members_can_invite_outside_collaborators]
    message = ""

    validate_setting value: setting_value, valid_values: %w(no_policy repository_admins_allowed organization_admins_only enterprise_admins_only)

    case setting_value
    when "repository_admins_allowed"
      this_business.allow_members_can_invite_outside_collaborators(actor: current_user, force: true)
      message = "Repository admins can now #{invite_or_add_action_word.downcase} #{outside_collaborators_verbiage(this_business)}."
    when "organization_admins_only"
      this_business.disallow_members_can_invite_outside_collaborators(actor: current_user, force: true)
      message = "Repository admins will not be able to #{invite_or_add_action_word.downcase} #{outside_collaborators_verbiage(this_business)}."
    when "enterprise_admins_only"
      this_business.enterprise_admins_only_can_invite_outside_collaborators(actor: current_user)
      message = "Enterprise owners only can now #{invite_or_add_action_word.downcase} #{outside_collaborators_verbiage(this_business)}."
    when "no_policy"
      this_business.clear_members_can_invite_outside_collaborators(actor: current_user)
      message = "Organization administrators can now change this setting for individual organizations."
    end

    redirect_to :back, notice: message
  end

  def update_members_can_change_repo_visibility # rubocop:todo GitHub/UseRestfulActions
    setting_value = params[:members_can_change_repo_visibility]&.to_s
    validate_setting value: setting_value

    message = ""
    case setting_value
    when "enabled"
      this_business.allow_members_to_change_repo_visibility(actor: current_user, force: true)
      message = "Members can change repository visibilities and this is enforced for this enterprise."
    when "disabled"
      this_business.block_members_from_changing_repo_visibility(actor: current_user, force: true)
      message = "Members cannot change repository visibilities and this is enforced for this enterprise."
    when "no_policy"
      this_business.clear_members_can_change_repo_visibility_setting(actor: current_user)
      message = "Policy removed for repository visibility change setting."
    end

    redirect_to settings_member_privileges_enterprise_path(this_business), notice: message
  end

  def update_allow_private_repository_forking # rubocop:todo GitHub/UseRestfulActions
    setting_value = params[:allow_private_repository_forking]&.to_s
    policy_value = params[:allow_private_repository_forking_policy]&.to_s

    # if forced, the org cannot override the value. we should only force if the business hasn't opted in to org policies.
    should_force = false
    validate_setting value: setting_value

    message = ""
    case setting_value
    when "enabled"
      result = this_business.allow_private_repository_forking(force: should_force, actor: current_user, policy: policy_value)
      if !result
        flash[:error] = "Could not set the private repository forking policy for #{this_business} at this time. Please ensure the policy is valid."
      else
        message = "Repository forking policy updated."
      end
    when "disabled"
      this_business.block_private_repository_forking(actor: current_user)
      message = "Private and internal repository forks are disabled and enforced for this enterprise."
    when "no_policy"
      this_business.clear_private_repository_forking_setting(actor: current_user)
      message = "Private and internal repository forks policy removed."
    end

    redirect_to settings_member_privileges_enterprise_path(this_business), notice: message
  end

  def update_default_repository_permission # rubocop:todo GitHub/UseRestfulActions
    valid_values = Configurable::DefaultRepositoryPermission.valid_values.map(&:to_s) + ["no_policy"]
    permission = params[:default_repository_permission]&.to_s
    validate_setting value: permission, valid_values: valid_values

    message = ""
    if "no_policy" == permission
      this_business.clear_default_repository_permission(actor: current_user)
      message = "The base repository permission policy is removed."
    else
      begin
        permission = permission.to_sym
        this_business.update_default_repository_permission permission, force: true, actor: current_user
        message = "The base repository permission is set to \
          \"#{Configurable::DefaultRepositoryPermission.human_friendly_value(permission)}\" \
          and is enforced for this enterprise.".squish
      rescue Configurable::DefaultRepositoryPermission::AlreadyUpdating
        flash[:error] = "The base repository permission is already being updated."
        return redirect_to settings_member_privileges_enterprise_path(this_business)
      end
    end

    redirect_to settings_member_privileges_enterprise_path(this_business), notice: message
  end

  private

  memoize def members_can_update_protected_branches_params
    params.require(:business).permit(:members_can_update_protected_branches)
  end

  memoize def members_can_delete_repos_params
    params.require(:business).permit(:members_can_delete_repositories)
  end

  memoize def members_can_delete_issues_params
    params.require(:business).permit(:members_can_delete_issues)
  end

  memoize def members_can_create_repos_params
    params.require(:business).permit(:members_can_create_repositories, :public, :private, :internal)
  end

  memoize def members_can_invite_outside_collaborators_params
    params.require(:business).permit(:members_can_invite_outside_collaborators)
  end

  def update_protected_branches_setting_flag_required
    render_404 unless GitHub.update_protected_branches_setting_enabled? || GitHub.flipper[:update_protected_branches_setting].enabled?(this_business)
  end

  def to_sentence(arr)
    return arr.first if arr.length == 1

    string = arr[0..-2].join(", ")
    string += "," if arr.length > 2 # Oxford commas keep it classy
    string += " and "
    string += arr.last

    string
  end
end
