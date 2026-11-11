# typed: true
# frozen_string_literal: true

class Orgs::Invitations::ReinstatedController < Orgs::Controller
  include Orgs::InvitationsControllerMethods

  before_action :login_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:show]

  def show
    status = Organization::JobStatus.find(params[:status])
    return head 404 unless status

    # Data not processed yet, so keep polling.
    unless status.finished?
      return head 202
    end

    respond_to do |format|
      format.html do
        render partial: "orgs/invitations/show_reinstated", locals: {
            organization: this_organization,
            continue_path: reinstate_return_to_path,
            layout: false,
          }
      end
    end
  end
end
