# frozen_string_literal: true

class ApplicationController < ActionController::Base
  layout "application"
  before_action :set_paper_trail_whodunnit

  # Override as you're able in individual controllers. The current_user_login
  # should be a string representing the curation agent's GitHub login.
  def current_user_login
    nil
  end

  # Store the GitHub login as the "whodunnit" in PaperTrail's version records.
  def user_for_paper_trail
    current_user_login
  end

  # Metadata keys added here must correspond to columns on the versions table.
  def info_for_paper_trail
    {
      request_id: request.request_id,
    }
  end

  def render_404
    render file: Rails.public_path.join("404.html"), status: :not_found
  end
end
