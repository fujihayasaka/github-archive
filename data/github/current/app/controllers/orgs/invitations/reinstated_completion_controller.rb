# typed: true
# frozen_string_literal: true

class Orgs::Invitations::ReinstatedCompletionController < Orgs::Controller
  include Orgs::InvitationsControllerMethods
  before_action :login_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:show]

  # GET: Safely redirects using the `return_to` parameter to prevent attackers
  # injecting malicious URLs into the restore process.
  # If `return_to` is not supplied we redirect to the Organization root path
  def show
    safe_redirect_to reinstate_return_to_path
  end
end
