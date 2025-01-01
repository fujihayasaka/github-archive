# typed: true
# frozen_string_literal: true

class Stafftools::Users::PronounsController < StafftoolsController
  before_action :ensure_user_not_org

  def destroy
    this_user.profile_pronouns = nil
    this_user.save!

    redirect_to stafftools_user_administrative_tasks_path(this_user)
  end
end
