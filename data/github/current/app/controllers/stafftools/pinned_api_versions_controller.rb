# typed: true
# frozen_string_literal: true

class Stafftools::PinnedApiVersionsController < StafftoolsController
  def update
    target = case params[:actor_type]
    when "User"
      User.find(params[:actor_id])
    when "OauthApplication"
      OauthApplication.find(params[:actor_id])
    when "Integration"
      Integration.find(params[:actor_id])
    else
      nil
    end

    if target.nil?
      render_404
    else
      # Turn an incoming `""` into `nil`
      new_version = params[:pinned_api_version].blank? ? nil : params[:pinned_api_version]
      target.update(pinned_api_version: new_version)
      if target.errors.any?
        flash[:error] = "Failed to update pinned API version: #{target.errors.full_messages.to_sentence}"
      end
      redirect_to :back
    end
  end
end
