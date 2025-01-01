# typed: true
# frozen_string_literal: true

class Hovercards::UsersController < ApplicationController
  before_action :require_xhr, only: [:show, :show_legacy]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Notify,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    # When rendering 404 for a logged in user,
    # their notifications are retrieved with the response.
    # This can hit all of NotificationsEntries, Mysql2, and Billing
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Notify,
    only: [:show_legacy]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    show_internal
  end

  def show_legacy # rubocop:todo GitHub/UseRestfulActions
    show_internal
  end

  private

  def show_internal
    return render_404 unless this_user

    default_tracking_data = {
      actor_id: current_user&.id,
      card_user_id: this_user.id,
      card_user_login: this_user.display_login,
      subject_type: primary_subject&.class&.name
    }

    hydro_params = params.slice(:event_type, :hover_target, :payload).to_unsafe_hash
    hydro_params[:payload] = hydro_params[:payload] || default_tracking_data

    render "hovercards/users/show", locals: {
      user: this_user,
      hovercard: hovercard,
      hydro_data: hydro_params
    }, layout: false
  end

  memoize def primary_subject
    type, id = params[:subject]&.split(":")
    subject = Hovercard::SUBJECT_PREFIX_MAP[type]&.find_by_id(id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    if subject.is_a?(Organization) && this_user&.is_enterprise_managed?
      biz = T.must(this_user.enterprise_managed_business)
      subject = nil unless biz.organizations.include?(subject)
    end
    subject
  end

  memoize def this_user
    return @user if @user

    if action_name == "show"
      user_login = params[:user_id]
      return unless user_login.present?

      @user = User.where(type: "User", login: user_login).first
    else
      user_id = params[:user_id]&.to_i
      user_login = params[:user_login].presence
      return unless user_id || user_login

      @user = User.where(type: "User").and(User.where(login: user_login).or(User.where(id: user_id))).first
    end
  end

  memoize def hovercard
    UserHovercard.new(this_user, primary_subject, viewer: current_user)
  end

  def target_for_conditional_access
    if this_user&.is_enterprise_managed?
      if hovercard.subject_organization
        biz = T.must(this_user.enterprise_managed_business)
        return hovercard.subject_organization if biz.organizations.include?(hovercard.subject_organization)
      end
      return this_user.enterprise_managed_business
    end
    hovercard.subject_organization || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
