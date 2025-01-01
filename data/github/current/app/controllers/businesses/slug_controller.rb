# typed: true
# frozen_string_literal: true

class Businesses::SlugController < Businesses::BusinessController
  include SharedBusinessActions

  before_action :login_required
  before_action :dotcom_required
  before_action :business_owner_required, only: [:update]
  before_action :check_rename_allowed, only: [:update]

  def update
    if params[:accept_conditions].blank?
      flash[:error] = "You must acknowledge that you've read and understood the implications of changing your enterprise URL."
      return redirect_to settings_profile_enterprise_path(this_business)
    end

    old_slug = this_business.slug

    success = this_business.rename_slug params[:new_slug], actor: current_user
    if success
      flash[:notice] = "Renamed enterprise URL to #{GitHub.url}#{enterprise_path(this_business)}."
    else
      this_business.restore_attributes
      flash[:error] = "Failed to rename enterprise URL slug. #{this_business.errors.full_messages.to_sentence}."
    end

    tags = ["success:#{success}", "new_slug:#{params[:new_slug]}", "slug_was:#{old_slug}"]
    GitHub.dogstats.increment("business.self_serve_slug_rename", tags: tags)

    redirect_to settings_profile_enterprise_path(this_business)
  end

  private

  def check_rename_allowed
    render_404 unless this_business.self_serve_url_change_permitted?
  end
end
