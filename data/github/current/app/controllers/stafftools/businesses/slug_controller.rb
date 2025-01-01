# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::SlugController < Stafftools::Businesses::BusinessBaseController
  def update
    if this_business.rename_slug params[:new_slug], actor: current_user
      flash[:notice] = "Renamed enterprise account URL slug to '#{params[:new_slug]}'."
    else
      this_business.restore_attributes
      flash[:error] = "Failed to rename URL slug. #{this_business.errors.full_messages.to_sentence}."
    end
    redirect_to stafftools_enterprise_path(this_business)
  end
end
