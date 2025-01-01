# typed: strict
# frozen_string_literal: true

class Settings::Keys::SshKeys::Organization::CredentialAuthorizationsController < ApplicationController
  include Settings::ControllerMethods
  include Organization::CredentialAuthorizationsHelper

  before_action :login_required

  stylesheet_bundle :settings
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  sig { void }
  def index
    public_key = current_user.public_keys.find_by(id: params[:key_id])
    return(render_404) unless public_key

    render(Organizations::CredentialAuthorizations::ListComponent.new(
      credential: public_key,
      org_credential_map: organization_credential_authorization_map(public_key),
      experimental: params[:experimental]
    ), layout: false)
  end
end
