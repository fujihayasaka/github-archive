# typed: true
# frozen_string_literal: true

class Stafftools::Users::InteractionBansController < StafftoolsController
  before_action :ensure_user_exists

  def create
    User::InteractionAbility.disallow_interactions(this_user)

    redirect_to stafftools_user_administrative_tasks_path(this_user)
  end

  def destroy
    User::InteractionAbility.allow_interactions(this_user)

    redirect_to stafftools_user_administrative_tasks_path(this_user)
  end
end
