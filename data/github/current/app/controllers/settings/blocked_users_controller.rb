# typed: true
# frozen_string_literal: true

class Settings::BlockedUsersController < ApplicationController
  include Settings::ControllerMethods

  before_action :login_required
  before_action :ensure_user_abuse_mitigation_enabled
  before_action :ensure_not_enterprise_managed
  before_action :ensure_target_user, only: [:create, :destroy, :update]
  before_action :ensure_not_current_user, only: [:create, :destroy, :update]

  stylesheet_bundle :settings
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    render "settings/blocked_users/index", locals: {
      display_login: params[:block_user],
      interaction_setting: interaction_setting,
    }
  end

  def create
    current_user.block(target_user, note: params[:note])

    if request.xhr?
      ignored = current_user.ignored_users.where(ignored_id: target_user.id).first
      render partial: "settings/blocked_users/user",
        locals: { user_ignore: ignored }
    else
      if params[:return_to].present?
        safe_redirect_to(params[:return_to], fallback: settings_blocked_users_path)
      else
        redirect_to settings_blocked_users_path
      end
    end
  end

  def destroy
    current_user.unblock(target_user)

    if params[:return_to].present?
      safe_redirect_to(params[:return_to], fallback: settings_blocked_users_path)
    else
      redirect_to settings_blocked_users_path
    end
  end

  def update
    ignored_user_record = current_user.ignored_users.find_by(ignored: target_user)

    if ignored_user_record.present?
      updated_note = params[:clear] == "true" ? nil : params[:note]

      if ignored_user_record.update(note: updated_note)
        flash[:notice] = [
          "The note was successfully",
          params[:clear] == "true" ? "cleared." : "updated.",
        ].join(" ")
      else
        flash[:error] = [
          "There was a problem saving the note:",
          ignored_user_record.errors.full_messages.to_sentence,
        ].join(" ")
      end
    else
      flash[:error] = "You are not currently blocking this user."
    end

    if params[:return_to].present?
      safe_redirect_to(params[:return_to], fallback: settings_blocked_users_path)
    else
      redirect_to settings_blocked_users_path
    end
  end

  private

  def ensure_target_user
    render_404 unless target_user
  end

  def ensure_not_current_user
    render_404 if target_user == current_user
  end

  def ensure_user_abuse_mitigation_enabled
    return render_404 unless GitHub.user_abuse_mitigation_enabled?
  end

  def ensure_not_enterprise_managed
    return render_404 if current_user.is_enterprise_managed?
  end

  def interaction_setting # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @interaction_setting ||= current_user.interaction_setting ||
      current_user.build_interaction_setting
  end

  # Private: Find the target user to be blocked / unblocked
  #
  # Returns a User|nil.
  memoize def target_user
    User.find_by(login: params[:id]) || User.find_by(login: params[:login])
  end
end
