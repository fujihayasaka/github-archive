# typed: true
# frozen_string_literal: true

class Stafftools::Users::StandardContractualClausesController < StafftoolsController
  before_action :ensure_user_exists

  def create
    this_user.flag_for_standard_contractual_clauses!(actor: current_user)

    redirect_to(
      stafftools_user_administrative_tasks_path(this_user),
      notice: "Succesfully flagged #{this_user} for Standard Contractual Clauses.",
    )
  end

  def destroy
    this_user.remove_standard_contractual_clauses_flag!(actor: current_user)

    redirect_to(
      stafftools_user_administrative_tasks_path(this_user),
      notice: "Succesfully removed SCC flag for #{this_user}.",
    )
  end
end
