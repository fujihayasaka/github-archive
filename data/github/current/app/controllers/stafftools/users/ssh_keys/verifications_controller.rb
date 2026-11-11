# typed: true
# frozen_string_literal: true

class Stafftools::Users::SshKeys::VerificationsController < StafftoolsController
  before_action :dotcom_required
  before_action :ensure_user_exists

  def create
    valid, messages = GitHub::SshVerification.validate(params[:token], this_user)

    redirect_to stafftools_user_ssh_keys_path(this_user, valid: valid, messages: messages)
  end
end
