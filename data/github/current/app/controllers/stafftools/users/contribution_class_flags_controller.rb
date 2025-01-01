# typed: true
# frozen_string_literal: true

class Stafftools::Users::ContributionClassFlagsController < StafftoolsController
  before_action :ensure_user_exists

  def update
    contribution_classes = params.fetch(:contribution_classes, []).map(&:constantize)
    this_user.flag_contribution_classes!(contribution_classes, actor: current_user)

    if contribution_classes.empty?
      flash[:notice] = "Successfully unflagged all contribution types for #{this_user}."
    else
      flagged_contributions = contribution_classes.map { |cc| cc.name.demodulize }
      flash[:notice] = "Successfully flagged #{flagged_contributions.join(", ")} for #{this_user}."
    end

    redirect_to stafftools_user_administrative_tasks_path(this_user)
  end
end
