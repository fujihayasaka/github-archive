# typed: true
# frozen_string_literal: true

class Businesses::DotcomConnectionSettingsRedirectController < Businesses::BusinessController
  before_action :enterprise_required
  before_action :login_required
  before_action :business_owner_required

  depends_on_clusters ApplicationRecord::Mysql1, only: %i(show)

  def show
    # This is needed as EnterpriseInstallationsController#show uses
    # a hardcoded url because cloud doesn't know the enterprise account
    # slug on the server instance to formulate a full enterprise route.
    redirect_path = request.fullpath.gsub \
      %r{/admin/[^/]+}i,
      "/enterprises/#{GitHub.global_business.to_param}/settings/dotcom_connection"
    safe_redirect_to redirect_path
  end
end
