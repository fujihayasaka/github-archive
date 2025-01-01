# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::RestoresController < Stafftools::Businesses::BusinessBaseController
  def create
    this_business.restore!
    flash[:notice] = "Restored #{this_business.name}"
    redirect_to :back
  end

  private

  # Override to require a soft-deleted Business
  memoize def this_business
    slug = params[:enterprise_slug] || params[:slug]
    ::Business.deleted.find_by(slug: slug)
  end
end
