# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::FeaturesController < Stafftools::SponsorsController
  def update
    is_featured = params[:is_featured]
    featured_state = is_featured ? :active : :allowed
    featured_description = params[:featured_description]

    this_listing.featured_state = featured_state
    this_listing.featured_description = featured_description
    this_listing.short_description = featured_description

    if this_listing.save
      verb = is_featured ? "featured" : "unfeatured"
      flash[:notice] = "Successfully #{verb} Sponsors membership for #{this_sponsorable}."
    else
      errors = this_listing.errors.full_messages
      flash[:error] = "Could not update featured state for Sponsors " \
        "membership: #{errors.to_sentence}"
    end

    redirect_to stafftools_sponsors_member_path(this_sponsorable)
  end
end
