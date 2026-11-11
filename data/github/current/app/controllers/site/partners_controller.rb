# typed: true
# frozen_string_literal: true

class Site::PartnersController < Site::BaseController
  layout "site"

  def index
    return Site::LandingPagesController.dispatch(:show, request, response) if FeatureFlag.vexi.enabled_or_raise?(:contentful_lp_partners, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

    render "site/partners/index"
  end
end
