# typed: true
# frozen_string_literal: true

class Businesses::AdminCenterOptionsController < Businesses::BusinessController
  include ActionView::Helpers::TextHelper

  before_action :enterprise_required
  before_action :business_owner_required
  before_action :option_prerequisites_required, only: :update

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  def index
    render "businesses/settings/admin_center_options", locals: { slug: this_business.slug }
  end

  def update
    case params[:option_name].to_s
    when "change_allow_force_push"
      change_allow_force_push
    when "change_allow_comment_author_profile_name"
      change_allow_comment_author_profile_name
    when "change_ssh_access"
      change_ssh_access
    when "change_suggested_protocol"
      change_suggested_protocol
    when "change_git_lfs_access"
      change_git_lfs_access
    when "change_showcase_access"
      change_showcase_access
    when "change_org_creation"
      change_org_creation
    when "change_org_membership_visibility"
      change_org_membership_visibility
    when "change_reactivate_suspended"
      change_reactivate_suspended
    when "change_reactivate_suspended_on_sync"
      change_reactivate_suspended_on_sync
    when "toggle_ldap_debugging"
      toggle_ldap_debugging
    when "change_ldap_search_depth"
      change_ldap_search_depth
    when "change_max_object_size"
      change_max_object_size
    when "change_repo_visibility"
      change_repo_visibility
    when "toggle_saml_debugging"
      toggle_saml_debugging
    when "change_cross_repo_conflict_editor"
      change_cross_repo_conflict_editor
    when "change_dormancy_threshold"
      change_dormancy_threshold
    when "change_anonymous_git_access"
      change_anonymous_git_access
    when "change_anonymous_git_access_locked"
      change_anonymous_git_access_locked
    else
      return render_404
    end

    redirect_to enterprise_admin_center_options_path(this_business)
  end

  private

  def option_prerequisites_required
    case params[:option_name].to_s
    when "change_anonymous_git_access_locked"
      render_404 unless GitHub.anonymous_git_access_enabled?
    end
  end

  def change_allow_force_push
    val = params[:value].presence || "false"
    policy = params[:force_push_policy].present? || false

    flash[:notice] = if val == "_clear"
      GitHub.clear_force_push_rejection(current_user)
      "Setting cleared. Instance default will be used."
    else
      GitHub.set_force_push_rejection val, current_user, policy
      policy_level = policy ? "and enforced for all repositories on the instance" : "by default"

      case val
      when "false"
        "Force pushing allowed #{policy_level}."
      when "all"
        "Force pushing blocked #{policy_level}."
      when "default"
        "Force pushing blocked on the default branch #{policy_level}."
      end
    end
  end

  def change_ssh_access
    val = params[:value].presence || false
    policy = params[:ssh_policy].present? || false

    flash[:notice] = if val == "_clear"
      GitHub.clear_ssh(current_user)
      "Setting cleared. Instance default will be used."
    else
      policy_level = policy ? "and enforced for all repositories on the instance" : "by default"
      if val.to_s == "true"
        GitHub.enable_ssh(current_user, policy)
        "Git SSH access enabled #{policy_level}."
      else
        GitHub.disable_ssh(current_user, policy)
        "Git SSH access disabled #{policy_level}."
      end
    end
  end

  def change_suggested_protocol
    val = params[:value]
    if val.in? %w(sticky http ssh)
      GitHub.set_suggested_protocol(val, current_user)
    else
      flash[:error] = "Invalid request."
    end

    flash[:notice] = case val
    when "sticky"
      "The last protocol selected by the user will be suggested."
    when "http"
      "HTTPS will be suggested."
    when "ssh"
      "SSH will be suggested."
    end
  end

  def change_git_lfs_access
    val = params[:value]

    if val == "true"
      GitHub.enable_git_lfs(current_user)
      flash[:notice] = "Git LFS support enabled."
    elsif val == "false"
      GitHub.disable_git_lfs(current_user)
      flash[:notice] = "Git LFS support disabled."
    end
  end

  def change_showcase_access
    val = params[:value]

    if val == "true"
      GitHub.enable_showcase(current_user)
      flash[:notice] = "Showcases enabled."
    elsif val == "false"
      GitHub.disable_showcase(current_user)
      flash[:notice] = "Showcases disabled."
    end
  end

  def change_max_object_size
    val = params[:value].presence

    if val
      policy = params[:max_object_policy].present? || false
      policy_level = policy ? "and enforced for all repositories on the instance" : "by default"

      GitHub.set_max_object_size(val.to_i, @current_user, policy)
      max_value = if val.to_i == 0
        "unlimited"
      else
        "#{val}MB"
      end
      flash[:notice] = "Maximum object size set to #{max_value} #{policy_level}."
    else
      flash[:error] = "Maximum object size value must be a positive integer or zero"
    end
  end

  def change_ldap_search_depth
    if depth = params[:search_depth].presence
      begin
        depth = Integer(depth)
        GitHub.config.set("ldap.search_strategy_depth", depth, current_user)
        flash[:notice] = "Search depth set to #{depth}."
      rescue ArgumentError
        flash[:error] = "Search depth must be a valid integer."
      end
    else
      GitHub.config.delete("ldap.search_strategy_depth", current_user)
      flash[:notice] = "Search depth cleared."
    end
  end

  def change_org_creation
    val = params[:value]

    if val == "true"
      GitHub.enable_org_creation(current_user)
      flash[:notice] = "User organization creation enabled."
    elsif val == "false"
      GitHub.disable_org_creation(current_user)
      flash[:notice] = "User organization creation disabled."
    end
  end

  # https://github.com/github/special-projects/issues/1112
  # Enable showing first and last name on issue/PR comment for public or internal scope.
  # This specific setting is only available for GHES
  def change_allow_comment_author_profile_name
    val = params[:value].presence || "false"
    enforce = params[:allow_comment_authors_profile_name_policy].present? || false
    enforced_message = enforce ? " and is enforced for all repositories on the instance." : "."

    if val.to_s == "true"
      this_business.enable_display_commenter_full_name(force: enforce, actor: current_user)
      flash[:notice] = "Public and internal repositories will now show comment author's full name#{enforced_message}"
    elsif val.to_s == "false"
      this_business.disable_display_commenter_full_name(force: enforce, actor: current_user)
      flash[:notice] = "Public and internal repositories will not show comment author's full name#{enforced_message}"
    end
  end

  def change_org_membership_visibility
    visibility = params[:value]
    enforce = params[:org_membership_visibility_enforcement].present?

    GitHub.set_default_org_membership_visibility(visibility, current_user, enforce)

    extra_text = enforce ? " and is enforced for all enterprise members." : "."
    flash[:notice] = "Organization membership visibility is now #{visibility} by default#{extra_text}"
  end

  def change_reactivate_suspended
    val = params[:value]

    if val == "true"
      GitHub.config.enable("auth.reactivate-suspended", current_user)
      flash[:notice] = "User reactivation enabled."
    else
      GitHub.config.disable("auth.reactivate-suspended", current_user)
      flash[:notice] = "User reactivation disabled."
    end
  end

  def change_reactivate_suspended_on_sync
    val = params[:value]

    if val == "true"
      GitHub.config.enable("auth.reactivate-suspended-on-sync", current_user)
      flash[:notice] = "User reactivation on sync enabled."
    else
      GitHub.config.disable("auth.reactivate-suspended-on-sync", current_user)
      flash[:notice] = "User reactivation on sync disabled."
    end
  end

  def toggle_ldap_debugging
    val = params[:value]

    if val == "true"
      GitHub.config.enable("ldap.debug_logging_enabled", current_user)
      flash[:notice] = "LDAP debugging enabled."
    else
      GitHub.config.delete("ldap.debug_logging_enabled", current_user)
      flash[:notice] = "LDAP debugging disabled."
    end
  end

  def toggle_saml_debugging
    val = params[:value]

    if val == "true"
      GitHub.config.enable("saml.debug_logging_enabled", current_user)
      flash[:notice] = "SAML debugging enabled."
    else
      GitHub.config.delete("saml.debug_logging_enabled", current_user)
      flash[:notice] = "SAML debugging disabled."
    end
  end

  def change_repo_visibility
    # The true/false cases here just handle requests in-flight when this is
    # deployed and can be removed in the future.
    val = case params[:value]
    when "true" then "private"
    when "false" then "public"
    else params[:value]
    end
    GitHub.set_default_repo_visibility(val, current_user) # value is validated by model
    flash[:notice] = "New repositories are #{val} by default."
  end

  def change_cross_repo_conflict_editor
    val = params[:value]

    if val == "true"
      GitHub.enable_cross_repo_conflict_editor(current_user)
      flash[:notice] = "Conflict editor is now enabled for resolving conflicts between repositories."
    elsif val == "false"
      GitHub.disable_cross_repo_conflict_editor(current_user)
      flash[:notice] = "Conflict editor is now disabled for resolving conflicts between repositories."
    end
  end

  def change_dormancy_threshold
    days = params[:dormancy_threshold_days]&.to_i ||
      Configurable::EnterpriseDormancyThreshold::DEFAULT_DORMANCY_THRESHOLD_DAYS

    if GitHub.set_enterprise_dormancy_threshold_days(days, current_user)
      flash[:notice] = "Dormancy threshold set to #{pluralize(days, "days")}."
    else
      flash[:error] = "Invalid dormancy threshold submitted."
    end
  end

  def change_anonymous_git_access
    val = params[:value]

    if val == "true"
      GitHub.enable_anonymous_git_access(current_user)
      flash[:notice] = "Anonymous Git read access can be enabled for repositories."
    elsif val == "false"
      GitHub.disable_anonymous_git_access(current_user)
      flash[:notice] = "Anonymous Git read access can no longer be enabled for repositories."
    end
  end

  def change_anonymous_git_access_locked
    val = params[:lock_setting]&.to_s
    if val == "true"
      GitHub.lock_anonymous_git_access(current_user, force: true)
      flash[:notice] = "Anonymous Git read access is now locked."
    else
      GitHub.unlock_anonymous_git_access(current_user)
      flash[:notice] = "Anonymous Git read access is now unlocked."
    end
  end
end
