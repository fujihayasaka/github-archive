# typed: true
# frozen_string_literal: true

class Site::Features::ProjectManagementController < Site::BaseController
  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  def index
    safe_redirect_to "/features/issues", status: 301
  end
end
