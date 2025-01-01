# typed: true
# frozen_string_literal: true

class Stafftools::AdminRedirectsController < StafftoolsController # rubocop:todo GitHub/ControllersShouldHaveTests

  before_action :ensure_enabled

  def users # rubocop:todo GitHub/UseRestfulActions
    redirect_to stafftools_users_path
  end

  def repositories # rubocop:todo GitHub/UseRestfulActions
    redirect_to stafftools_repositories_path
  end

  private

  def ensure_enabled
    redirect_to stafftools_path unless GitHub.admin_enabled?
  end
end
