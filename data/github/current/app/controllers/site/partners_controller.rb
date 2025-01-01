# typed: true
# frozen_string_literal: true

class Site::PartnersController < Site::BaseController
  layout "site"

  def index
    render "site/partners/index"
  end
end
