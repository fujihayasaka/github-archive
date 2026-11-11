# typed: true
# frozen_string_literal: true

class FeaturePreviewController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  skip_before_action :perform_conditional_access_checks, only: [:index, :toggle] # rubocop:todo GitHub/DoNotSkipCapBeforeAction
  before_action :require_xhr, except: [:toggle]
  before_action :login_required
  before_action :require_feature_flags

  after_action :update_seen_features, only: :index

  allow_verified_fetch only: [:toggle]

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

    render json: {
      features: features.map do |feature|
        {
          slug: feature.slug,
          name: feature.public_name,
          description_html: GitHub::Goomba::MarkdownPipeline.to_html(feature.description, cache_settings: { use_cache: true }),
          feedback_link: feature.feedback_link,
          image_link: feature.image_link,
          documentation_link: feature.documentation_link,
          enrolled: current_user.prerelease_feature_enrollments[feature.id][:enabled],
          toggle_feature_path: feature_previews_toggle_path(feature_id: feature.slug),
        }
      end
    }
  end

  def toggle # rubocop:todo GitHub/UseRestfulActions
    feature_name = params[:feature_id]

    return render_404 unless user_feature_enabled?(feature_name)

    if current_user&.feature_preview_enabled?(feature_name)
      current_user&.disable_feature_preview(feature_name)
      enabled = false
    else
      current_user&.enable_feature_preview(feature_name)
      enabled = true
    end

    if request&.xhr?
      head :ok
    else
      friendly_feature_name = params[:friendly_feature_name]

      redirect_uri = Addressable::URI.parse(request.referrer)

      redirect_uri.query_values = {
        friendly_feature_name => enabled,
      } if friendly_feature_name

      safe_redirect_to(redirect_uri.to_s, fallback: :back)
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
