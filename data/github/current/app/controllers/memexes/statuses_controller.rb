
# typed: true
# frozen_string_literal: true

class Memexes::StatusesController < Memexes::Controller
  extend T::Sig

  include ApplicationController::VerifiedFetchDependency

  before_action :login_required, except: [:index]
  before_action :require_verified_email, except: [:index]
  before_action :require_memex_feature_enabled
  before_action :require_this_memex
  before_action :require_status, only: [:update, :destroy]
  before_action :ensure_spammy_user_own_content, only: [:update, :destroy]
  before_action :user_has_write_access, only: [:create, :update, :destroy]
  before_action :user_has_read_access, only: [:index]

  allow_verified_fetch only: [:create, :update, :destroy]

  depends_on_clusters ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:index]

  def index
    statuses = this_memex.memex_project_statuses.filter_spam_for(current_user).order(created_at: :desc)
    status_hash = statuses.map { |s| s.to_hash(current_user, cap_filter) }

    response_hash = {
      statuses: status_hash,
      form: {
        status: {
          options: MemexProjectStatus.status_options,
        },
      },
    }

    render(json: response_hash.deep_transform_keys { |k| k.to_s.camelize(:lower) })
  end

  def create
    new_status = MemexProjectStatus.build_for_project(this_memex, current_user, status_params)

    if new_status.save
      deliver(new_status)
    else
      render_json_error(
        error: new_status.errors.full_messages.to_sentence,
        status: :unprocessable_entity
      )
    end
  end

  def update
    status.status_id = status_params[:status_id]
    status.start_date = status_params[:start_date]
    status.target_date = status_params[:target_date]
    status.status_value = {
      status_id: status_params[:status_id],
      start_date: status_params[:start_date],
      target_date: status_params[:target_date],
    }.to_json
    status.body = status_params[:body]

    if status.save
      deliver(status)
    else
      render_json_error(
        error: status.errors.full_messages.to_sentence,
        status: :unprocessable_entity
      )
    end
  end

  def destroy
    status.destroy

    head :no_content
  end

  private

  memoize def status
    this_memex.memex_project_statuses.find_by(id: status_params[:id])
  end

  def require_status
    render_404 unless status
  end

  def ensure_spammy_user_own_content
    if current_user.spammy? && status.creator != current_user
      render_json_error(
        error: "Action unable to be performed by flagged user",
        status: :unprocessable_entity
      )
    end
  end

  def status_params
    underscored_params
      .permit(
        :id,
        :memex_id,
        :body,
        :status_id,
        :start_date,
        :target_date,
      )
  end

  def deliver(memex_project_status)
    status_response = {
      status: memex_project_status.to_hash(current_user, cap_filter)
    }

    if memex_status_updates_notifications_enabled?
      status_response[:viewer_is_subscribed] = notifyd_subscription.viewer_is_subscribed?
    end

    render(json: status_response.deep_transform_keys { |k| k.to_s.camelize(:lower) })
  end

  memoize def notifyd_subscription
    MemexProject::NotifydSubscriptions.new(current_user, this_memex)
  end
end
