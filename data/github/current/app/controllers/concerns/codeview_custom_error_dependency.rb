# typed: true
# frozen_string_literal: true

module CodeviewCustomErrorDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  include Repos::DataRouterDependency

  abstract!

  requires_ancestor { ApplicationController }

  sig { abstract.returns(T.untyped) }
  def app_payload; end

  def render_error(http_status, status, title, payload_class: nil, nested_class: nil, extra_nested_payloads: [])
    error_payload = helpers.repo_error_payload({ httpStatus: http_status, type: "httpError" })

    # Set @rendering_react_view right before render_react_app and after any potential failure paths, so that the
    # correct layout template for the React app is used. Temporary, until all paths in controller are React based.
    @rendering_react_view = true

    respond_with_react(
      app_name: "code-view",
      app_payload_generator: -> { app_payload },
      payload: payload_class.new(error_payload),
      nested_payloads: -> {
        layouts = [
          layout_route_payload,
          file_tree_layout_payload(error: true),
          Repos::CodeViewPayloads::BlobLayoutStyledBlobPayload.new({
            rawLines: nil,
            stylingDirectives: nil,
            colorizedLines: nil,
          }),
          *extra_nested_payloads
        ]
        layouts << nested_class.new(error_payload) if nested_class.present?
        layouts
      },
      title: title,
      turbo: {
        id: "repo-content-turbo-frame",
        target: "_top",
        action: "advance",
        class: helpers.full_height? ? "d-flex flex-auto" : ""
      },
      status: status
    )
  end

  def render_codeview_404(payload_class: nil, nested_class: nil, extra_nested_payloads: [])
    render_error(404, :not_found, "File not found", payload_class: payload_class, nested_class: nested_class, extra_nested_payloads: extra_nested_payloads)
  end

  def render_codeview_500(payload_class: nil, nested_class: nil, extra_nested_payloads: [])
    render_error(500, :internal_server_error, "Server Error", payload_class: payload_class, nested_class: nested_class, extra_nested_payloads: extra_nested_payloads)
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
