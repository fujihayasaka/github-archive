# typed: true
# frozen_string_literal: true

class Apps::BetaFeaturesController < ApplicationController
  include OrganizationsHelper
  include OauthApplicationsHelper

  before_action :login_required_or_org_admins_only
  before_action :sudo_filter

  before_action :find_feature_flag
  before_action :application

  def enable # rubocop:todo GitHub/UseRestfulActions
    FeatureFlag.vexi_management.add_feature_flag_actors(feature_flag, [application]) # rubocop:disable GitHub/FeatureManagement/NoVexiManagementUsage

    flash[:notice] = "#{feature_name} is being enabled for #{application.name}."
    redirect_to settings_oauth_application_beta_features_path(application)
  end

  def disable # rubocop:todo GitHub/UseRestfulActions
    FeatureFlag.vexi_management.remove_feature_flag_actors(feature_flag, [application]) # rubocop:disable GitHub/FeatureManagement/NoVexiManagementUsage

    flash[:notice] = "#{feature_name} is being disabled for #{application.name}."
    redirect_to settings_oauth_application_beta_features_path(application)
  end

  private

  memoize def feature_name
    Apps::BetaFeatureComponent::BETA_FEATURES[feature_flag][:title]
  end

  memoize def application
    current_context.oauth_applications.find(params[:id])
  end

  memoize def feature_flag
    params[:feature_flag]&.to_sym
  end

  def find_feature_flag
    render_404 unless Apps::BetaFeatureComponent::BETA_FEATURES.key?(feature_flag)
  end
end
