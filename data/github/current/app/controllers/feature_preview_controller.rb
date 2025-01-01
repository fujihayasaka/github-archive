# typed: true
# frozen_string_literal: true

class FeaturePreviewController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  skip_before_action :perform_conditional_access_checks, only: [:index, :enroll, :unenroll, :indicator_check] # rubocop:todo GitHub/DoNotSkipCapBeforeAction
  before_action :require_xhr, except: :indicator_check
  before_action :login_required
  before_action :require_feature_flags

  after_action :update_seen_features, only: :index

  allow_verified_fetch only: [:enroll, :unenroll]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    only: [:indicator_check]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    only: [:index]

  def index
    features = current_user.available_prerelease_features.sort_by(&:slug)

    selected_feature = features.find { |f| f.slug == params[:selected_slug] }
    selection_type = selected_feature ? "user_selected" : "default"
    selected_feature ||= features.first

    if selected_feature
      GlobalInstrumenter.instrument("feature_preview.selected", {
        user: current_user,
        feature: selected_feature,
        selection_type: selection_type,
      })
    end

    respond_to do |format|
      format.html do
        render partial: "feature_preview/dialog", locals: {
          features: features,
          enrollments: current_user.prerelease_feature_enrollments,
          selected_feature: selected_feature,
        }
      end
    end
  end

  def enroll # rubocop:todo GitHub/UseRestfulActions
    feature = Feature.find_by(slug: params[:feature_id])
    result = feature&.enroll(current_user)

    if result
      respond_to do |format|
        format.html do
          render partial: "feature_preview/dialog", locals: {
            features: current_user.available_prerelease_features.sort_by(&:slug),
            enrollments: current_user.prerelease_feature_enrollments,
            selected_feature: feature,
          }
        end
      end
    else
      respond_to do |format|
        format.json do
          return head :not_found
        end
      end
    end
  end

  def unenroll # rubocop:todo GitHub/UseRestfulActions
    feature = Feature.find_by(slug: params[:feature_id])
    result = feature&.unenroll(current_user)

    if result
      respond_to do |format|
        format.html do
          render partial: "feature_preview/dialog", locals: {
            features: current_user.available_prerelease_features.sort_by(&:slug),
            enrollments: current_user.prerelease_feature_enrollments,
            selected_feature: feature,
          }
        end
      end
    else
      respond_to do |format|
        format.json do
          return head :not_found
        end
      end
    end
  end

  def indicator_check # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "feature_preview/indicator", locals: { show_indicator: current_user.new_prerelease_features? }
      end

      format.json do
        has_features = current_user.new_prerelease_features?
        # if there are no new features to notify the user about
        # ask the browser to cache the negative result for while
        expires_in 15.minutes unless has_features
        render json: { show_indicator: has_features }
      end
    end
  end

  private

  def require_feature_flags
    unless feature_preview_enabled?
      head :not_found
    end
  end

  def update_seen_features
    unseen_features = current_user.unseen_prerelease_features
    if unseen_features.any?
      ActiveRecord::Base.connected_to(role: :writing) do
        Feature.transaction do
          unseen_features.each do |feature|
            feature.user_seen_features.create_or_find_by(user: current_user)
            GitHub.dogstats.increment("feature_preview.seen_features", tags: ["feature:#{feature.slug}"])
          end
        end
      end
    end
  end
end
