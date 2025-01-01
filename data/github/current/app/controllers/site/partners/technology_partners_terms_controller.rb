# typed: true
# frozen_string_literal: true

class Site::Partners::TechnologyPartnersTermsController < Site::BaseController
  layout "site"

  # Please do not copy or replicate this code. We're disabling linting rule to allow dynamic template rendering for the TPE site migration. We have consulted the marketing-engineering team and we have been instructed to do so. You can read more about the project at this issue https://github.com/github/technology-partnerships-and-engineering/issues/3189
  def index
    render "site/partners/technology_partners_terms/index" # rubocop:disable GitHub/RailsViewRenderPathsExist, GitHub/RailsControllerRenderLiteral
  end
end
