# typed: true
# frozen_string_literal: true

class Site::Features::SecurityController < Site::Features::BaseController
  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  stylesheet_bundle "feature-security"

  def index
    render "site/features/security/index"
  end
end
