# typed: true
# frozen_string_literal: true

module ApplicationController::TurboDependency
  extend T::Helpers
  extend ActiveSupport::Concern
  include ApplicationController::PjaxDependency

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))
    helper_method :turbo_type, :turbo_frame_request?, :turbo_visit_request?, :turbo_request_wants_repo_content_container?
  end

  def turbo_type
    return "frame" if turbo_frame_request?
    return "visit" if turbo_visit_request?
    nil
  end

  def turbo_frame_request?
    request.headers["Turbo-Frame"].present?
  end

  def turbo_frame_container
    return @turbo_frame_container if defined? @turbo_frame_container

    @turbo_frame_container = request.headers["Turbo-Frame"].presence
  end

  def turbo_visit_request?
    request.headers["Turbo-Visit"].present?
  end

  # Always set Vary: Turbo-Visit, Turbo-Frame
  #
  # Ensures Turbo requests are always cached seperately from their full response
  # counterparts.
  def set_vary_turbo
    add_headers_to_vary(%w(Turbo-Visit Turbo-Frame))

    response.headers["X-Fetch-Nonce"] = current_nonce if turbo_type.present?
  end

  # We want to respond with a minimal layout for partial requests
  # respond with full application layout for ordinary html requests
  def layout_for_turbo_request(default_layout = "application")
    return "layouts/frame_navigation" if pjax? || turbo_frame_request?

    default_layout
  end

  # Is this a Turbo request that will replace content into the
  # `repo-content-turbo-frame` element?
  #
  # Returns a Boolean.
  def turbo_request_wants_repo_content_container?
    return @turbo_request_wants_repo_content_container if defined? @turbo_request_wants_repo_content_container

    @turbo_request_wants_repo_content_container = turbo_frame_request? && turbo_frame_container == "repo-content-turbo-frame"
  end
end
