# typed: true
# frozen_string_literal: true

class Site::Partners::LegalController < Site::BaseController
  def index
    return Site::LandingPagesController.dispatch(:show, request, response) if FeatureFlag.vexi.enabled_or_raise?(:contentful_lp_partners, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

    render "site/partners/legal/index"
  end

  # Please do not copy or replicate this code. We're disabling linting rule to allow dynamic template rendering for the TPE site migration. We have consulted the marketing-engineering team and we have been instructed to do so. You can read more about the project at this issue https://github.com/github/technology-partnerships-and-engineering/issues/3189
  def show
    resource_id = params[:id].gsub("-", "_")
    path = "site/partners/legal/#{resource_id}"

    if template_exists?(path)
      render template: path # rubocop:disable GitHub/RailsControllerRenderLiteral
    else
      render_404
    end
  end

  private

  def template_exists?(path)
    lookup_context.find_all(path).any?
  end
end
