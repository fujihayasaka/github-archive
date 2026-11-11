# typed: true
# frozen_string_literal: true

class Devtools::ToggleableFeaturesController < DevtoolsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :index],
    optional: true

  FEATURES_PER_PAGE = 100

  def index
    features = Feature.all
    render "devtools/toggleable_features/index", locals: { features: features }
  end

  def show
    feature = Feature.find_by!(slug: params[:id])
    render "devtools/toggleable_features/show", locals: { feature: feature }
  end

  def new
    feature = Feature.new
    render "devtools/toggleable_features/new", locals: { feature: feature }
  end

  def create
    feature = Feature.new(feature_params)

    if feature.save
      redirect_to devtools_toggleable_feature_path(feature.slug), notice: "'#{feature.public_name}' has been created"
    else
      render "devtools/toggleable_features/new", locals: { feature: feature }
    end
  end

  def edit
    feature = Feature.find_by!(slug: params[:id])
    render "devtools/toggleable_features/edit", locals: { feature: feature }
  end

  def update
    feature = Feature.find_by!(slug: params[:id])

    if feature.update(feature_params)
      redirect_to devtools_toggleable_feature_path(feature.slug), notice: "'#{feature.public_name}' has been updated"
    else
      render "devtools/toggleable_features/edit", locals: { feature: feature }
    end
  end

  def destroy
    feature = Feature.find_by!(slug: params[:id])
    feature.destroy

    redirect_to devtools_toggleable_features_path, notice: "#{feature.public_name} has been deleted"
  end

  def publish # rubocop:todo GitHub/UseRestfulActions
    feature = Feature.find_by!(slug: params[:toggleable_feature_id])

    feature.touch(:published_at)
    flash[:notice] = "#{feature.public_name} has been published"

    redirect_to devtools_toggleable_feature_path(feature.slug)
  end

  def unpublish # rubocop:todo GitHub/UseRestfulActions
    feature = Feature.find_by!(slug: params[:toggleable_feature_id])

    feature.update(published_at: nil)
    flash[:notice] = "#{feature.public_name} has been unpublished"

    redirect_to devtools_toggleable_feature_path(feature.slug)
  end

  private

  def set_default_nav_breadcrumb
    return unless header_redesign_enabled?

    feature = Feature.find_by(slug: params[:id])

    if feature
      set_nav_breadcrumb ContextRegion::Devtools::ToggleableFeatureCrumb.new(feature)
    else
      set_nav_breadcrumb ContextRegion::Devtools::ToggleableFeaturesIndexCrumb.new
    end
  end

  def feature_params
    params.require(:feature).permit(
      :public_name, :slug, :description, :feedback_link, :image_link, :documentation_link,
      :enrolled_by_default, :feature_flag_name
    )
  end
end
