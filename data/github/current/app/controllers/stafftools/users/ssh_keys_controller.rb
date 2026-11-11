# typed: true
# frozen_string_literal: true

class Stafftools::Users::SshKeysController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  before_action :ensure_user_exists

  layout :security_layout

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    keys_view = Stafftools::User::KeysView.new(user: this_user)

    render(
      "stafftools/users/ssh_keys/index",
      locals: { view: keys_view, valid: params[:valid], messages: params[:messages] },
    )
  end

  def destroy
    key = this_user.public_keys.find_by_id(params[:id].presence&.to_i)

    unless key
      flash[:error] = "The SSH key could not be found."
      return redirect_to stafftools_user_ssh_keys_path(this_user)
    end

    if key.destroy_with_explanation(:removed_by_staff)
      flash[:notice] = "The SSH key has been deleted."
    else
      flash[:error] = "Error deleting the SSH key."
    end

    redirect_to stafftools_user_ssh_keys_path(this_user)
  end
end
