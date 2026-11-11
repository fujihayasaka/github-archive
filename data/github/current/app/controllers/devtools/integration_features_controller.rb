# typed: true
# frozen_string_literal: true

class Devtools::IntegrationFeaturesController < DevtoolsController
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
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :new],
    optional: true

  def index
    visible = !!(params[:visible] == "true" || params[:visible].blank?)
    if visible
      integration_features = ::IntegrationFeature.at_least_visible
    else
      integration_features = ::IntegrationFeature.not_visible
    end
    integration_features = integration_features.order(:name)

    render "devtools/integration_features/index",
      locals: { integration_features: integration_features, visible: visible }
  end

  def new
    integration_feature = ::IntegrationFeature.new

    render "devtools/integration_features/new",
      locals: { integration_feature: integration_feature }
  end

  def edit
    integration_feature = find_integration_feature

    render "devtools/integration_features/edit",
      locals: { integration_feature: integration_feature }
  end

  def update
    integration_feature = find_integration_feature

    if integration_feature.update(integration_feature_params)
      redirect_to devtools_integration_features_path, notice: "App updated successfully!"
      nil
    else
      flash.now[:error] = "Error updating the app"
      render "devtools/integration_features/edit",
        locals: { integration_feature: integration_feature }
      nil
    end
  end

  def create
    integration_feature = ::IntegrationFeature.new(integration_feature_params)

    if integration_feature.save
      redirect_to devtools_integration_features_path, notice: "'#{integration_feature.name}' has been created"
      nil
    else
      flash.now[:error] = "Error creating the app"
      render "devtools/integration_features/new", locals: {
        integration_feature: integration_feature,
      }
      nil
    end
  end

  private

  def integration_feature_params
    params.require(:integration_feature).permit(:name, :body, :state)
  end

  def find_integration_feature
    ::IntegrationFeature.find(params[:id])
  end

  def set_default_nav_breadcrumb
    return unless header_redesign_enabled?

    set_nav_breadcrumb ContextRegion::BasicCrumb.new(nil,
      label: "GitHub Apps",
      path: devtools_integration_features_path,
      parent: ContextRegion::DevtoolsCrumb.new
    )
  end
end
