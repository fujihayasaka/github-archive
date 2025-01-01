# typed: true
# frozen_string_literal: true

class Site::Partners::IntegrationResourcesController < Site::BaseController
  layout "site"

  # Please do not copy or replicate this code. We're disabling linting rule to allow dynamic template rendering for the TPE site migration. We have consulted the marketing-engineering team and we have been instructed to do so. You can read more about the project at this issue https://github.com/github/technology-partnerships-and-engineering/issues/3189
  def show
    if params[:resource].present?
      resource_name = params[:resource].gsub("-", "_")
    end

    if params[:year].present? && params[:month].present? && params[:day].present?
      date_prefix = "#{params[:year]}_#{params[:month].rjust(2, '0')}_#{params[:day].rjust(2, '0')}_"
      resource_name = "#{date_prefix}#{resource_name}"
    end

    path = "site/partners/integration_resources/#{resource_name}"

    if template_exists?(path)
      render template: path # rubocop:disable GitHub/RailsViewRenderPathsExist, GitHub/RailsControllerRenderLiteral
    else
      render_404
    end
  end

  private

  def template_exists?(path)
    lookup_context.find_all(path).any?
  end
end
