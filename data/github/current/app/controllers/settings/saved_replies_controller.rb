# typed: true
# frozen_string_literal: true

module Settings
  class SavedRepliesController < ApplicationController

    include Issues::RateLimitsDependency

    # The following actions do not require conditional access checks because
    # they *don't* access any protected organization resources.
    # CAP bypass because this controller interacts with current_user and login_required.
    # rubocop:disable GitHub/DoNotSkipCapBeforeAction
    skip_before_action :perform_conditional_access_checks, only: %w(
      index
      create
      update
      edit
      destroy
    ) # rubocop:disable GitHub/DoNotSkipCapBeforeAction

    before_action :login_required
    before_action :highlight_settings_sidebar, only: [:edit]

    javascript_bundle :settings
    stylesheet_bundle :settings

    depends_on_clusters ApplicationRecord::Ballast,
      ApplicationRecord::Billing,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::Iam,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Memex,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Mysql5,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Repositories,
      ApplicationRecord::Spokes,
      optional: false, only: [:index]

    depends_on_clusters ApplicationRecord::Ballast,
      ApplicationRecord::Billing,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Mysql5,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Repositories,
      optional: false, only: [:edit]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index, :edit], optional: true

    RATE_LIMITS_FEATURES = [
      :issues_service_mutative_actions_rate_limits, # are rate limits for issues-owned controller/actions enabled
      :issues_service_mutative_actions_rate_limits_new_max, # what are the new max rate limits for issues-owned controller/actions
      :issues_rate_limit_circuit_breaker, # whether to enable the circuit breaker for spammy users creating issues via issues#create
    ]

    preload_features RATE_LIMITS_FEATURES

    rate_limit_requests \
      max: :issues_service_rate_limits_max,
      ttl: 1.hour,
      key: :default_rate_limit_key,
      at_limit: :issues_service_rate_limits_at_limit,
      if: :issues_service_rate_limits_enabled?

    def index
      respond_to do |format|
        format.html do
          if request.xhr? && !pjax?
            render partial: "settings/user/replies/menu", locals: {
              replies: user_replies,
            }
          else
            return_to = request.referrer if params[:return_to]
            render "settings/user/replies/index", locals: {
              replies: user_replies,
              reply: SavedReply.new,
              return_to: return_to,
            }
          end
        end

        format.json do
          render json: user_replies.map {
            |r| {
              id: r.id,
              title: r.title,
              body: r.body,
              default: r.default?,
            }
          }
        end
      end
    end

    def create
      reply = current_user.saved_replies.create(title: params[:title], body: params[:body])

      if reply.save
        GitHub.dogstats.increment("saved_reply", tags: ["action:create"])
        flash[:notice] = "Your saved reply was created successfully."
        if params[:return_to]
          safe_redirect_to params[:return_to]
        else
          redirect_to :back
        end
      else
        if reply.errors.include?(:reply_count)
          flash[:error] = "You’ve reached the maximum number of #{SavedReply::MAX_REPLIES_PER_USER} saved replies."
        else
          flash[:error] = "Error creating your saved reply."
        end
        redirect_to :back
      end
    end

    def edit
      reply = current_user.saved_replies.find(params[:id])
      render "settings/user/replies/edit", locals: { reply: reply }
    end

    def update
      reply = current_user.saved_replies.find(params[:id])
      if reply.update(title: params[:title], body: params[:body])
        GitHub.dogstats.increment("saved_reply", tags: ["action:update"])
        flash[:notice] = "Your saved reply was updated successfully."
        redirect_to saved_replies_path
      else
        flash[:error] = "Error updating your saved reply."
        render "settings/user/replies/edit", locals: { reply: reply }
      end
    end

    def destroy
      reply = current_user.saved_replies.find(params[:id])
      reply.destroy
      GitHub.dogstats.increment("saved_reply", tags: ["action:destroy"])

      if request.xhr?
        head :ok
      else
        flash[:notice] = "Your saved reply was deleted successfully."
        redirect_to saved_replies_path
      end
    end

    private

    def highlight_settings_sidebar
      @selected_link = :edit_saved_reply
    end

    def user_replies
      context = (params[:context].presence || "none").to_sym
      current_user.available_saved_replies(context: context)
    end
  end
end
