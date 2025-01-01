# typed: true
# frozen_string_literal: true

class Orgs::Invitations::EditRedirectionController < Orgs::Controller
  include Orgs::InvitationsControllerMethods

  before_action :login_required
  before_action :organization_admin_required

  def create
    identifier = (params[:identifier] ||= "").strip

    return render_404 unless identifier.present?

    if User.valid_email?(identifier)
      redirect_to org_edit_email_invitation_path(this_organization, email: identifier, enable_tip: params[:enable_tip].presence)
    else
      redirect_to org_edit_invitation_path(this_organization, identifier, enable_tip: params[:enable_tip].presence)
    end
  end
end
