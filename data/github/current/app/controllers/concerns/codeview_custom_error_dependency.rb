# typed: true
# frozen_string_literal: true

module CodeviewCustomErrorDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  abstract!

  requires_ancestor { ApplicationController }
  requires_ancestor { ReactHelper }

  sig { abstract.returns(T.untyped) }
  def app_payload; end

  def render_error(http_status, status, title)
    add_client_feature_flag(Repos::ReactPayload.code_view_feature_flags)

    error_payload = helpers.repo_error_payload({ httpStatus: http_status, type: "httpError" })

    # Set @rendering_react_view right before render_react_app and after any potential failure paths, so that the
    # correct layout template for the React app is used. Temporary, until all paths in controller are React based.
    @rendering_react_view = true
    render_react_app(
      app_payload_generator: -> () { app_payload },
      payload: error_payload,
      page_data: { selected_link: :repo_source, send_vitals: true },
      title: title,
      turbo: {
        id: "repo-content-turbo-frame",
        target: "_top",
        action: "advance",
        class: helpers.full_height? ? "d-flex flex-auto" : ""
      },
      ssr: false,
      status: status
    )
  end

  def render_codeview_404
    render_error(404, :not_found, "File not found")
  end

  def render_codeview_500
    render_error(500, :internal_server_error, "Server Error")
  end

  def custom_codeview_404?(skip_ff_check = false)
    return false if request.headers["Accept"] == "application/json"

    # It needs the react_repos_code_view_enabled flag to show the CodeView
    skip_ff_check || react_repos_view_enabled?
  end

  def react_repos_view_enabled?
    return @react_repos_code_view if instance_variable_defined?(:@react_repos_code_view)
    @react_repos_code_view = helpers.code_view_enabled?
  end
end
