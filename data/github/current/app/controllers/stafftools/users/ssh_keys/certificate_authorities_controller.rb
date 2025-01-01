# typed: true
# frozen_string_literal: true

class Stafftools::Users::SshKeys::CertificateAuthoritiesController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  before_action :ensure_user_exists
  before_action :ensure_org_not_user

  layout :security_layout

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    view = create_view_model(
      Stafftools::Organization::SshCertificateAuthoritiesView,
      org: this_user,
    )
    render "stafftools/organizations/ssh_keys/certificate_authorities/index", locals: { view: view }
  end

  def destroy
    ca = this_user.ssh_certificate_authorities.find_by_id!(params[:id].presence&.to_i)
    unless ca
      flash[:error] = "SSH certificate authority not found"
      return redirect_to stafftools_user_ssh_keys_certificate_authorities_path(this_user)
    end

    if ca.destroy
      flash[:notice] = "SSH certificate authority destroyed"
    else
      flash[:error] = "Error deleting SSH certificate authority"
    end
    redirect_to stafftools_user_ssh_keys_certificate_authorities_path(this_user)
  end
end
