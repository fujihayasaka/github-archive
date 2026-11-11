# typed: true
# frozen_string_literal: true

class AccountlessConfirmationsController < AccountVerificationsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Authnd,
    ApplicationRecord::SignupFlow,
    only: [:show]

  def show
    verify_accountless_email(params[:token])
  end
end
