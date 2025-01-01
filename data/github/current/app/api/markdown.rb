# typed: true
# frozen_string_literal: true

class Api::Markdown < Api::App
  include ReceiveSchemaWithOpenApi
  MAX_CONTENT_SIZE = 400.kilobytes
  MARKDOWN_MIME_TYPES = Set.new(%w(text/plain text/x-markdown))

  allow_media("text/html")

  post "/markdown/raw", operation_id: "markdown/render-raw" do
    control_access :apps_audited,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    unless MARKDOWN_MIME_TYPES.include? request.media_type
      deliver_error!(415,
        message: "Invalid request media type (expecting 'text/plain')",
        documentation_url: @documentation_url)
    end

    deliver_raw(render_md(request.body.read), content_type: "text/html;charset=utf-8")
  end

  post "/markdown", operation_id: "markdown/render" do
    control_access :apps_audited,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive(Hash)
    text = data["text"]

    if !text.is_a?(String)
      deliver_error! 422,
        message: "Missing or invalid 'text' attribute in JSON request",
        documentation_url: @documentation_url
    end

    mode = data["mode"] || "markdown"
    context = render_context(data["context"])

    md = render_md(text, mode, context, current_user)
    # Introducing strict validation of the markdown.create
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    _ = receive_with_schema("markdown", "create", skip_validation: true)
    deliver_raw(md, content_type: "text/html;charset=utf-8")
  end

  private

  def render_context(repo_path)
    return nil unless repo_path =~ Repository::NAME_WITH_OWNER_PATTERN

    if (repo = Repository.nwo(repo_path))
      set_current_repo_for_access_control(repo)
      repo if access_allowed?(:get_contents, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true)
    end
  end

  def render_md(text, mode = "markdown", repo = nil, user = nil)
    deliver_too_large_error! if text.size > MAX_CONTENT_SIZE

    headers["X-CommonMarker-Version"] = CommonMarker::VERSION

    case mode
    when "gfm"
      GitHub::Goomba::MarkdownPipeline.to_html(text, {
                                               entity: repo, current_user: user, base_url: GitHub.url,
                                               hide_snippet_buttons: true }, nil
                                               )

    when "markdown"
      commonmarker_opts = [:UNSAFE, :FOOTNOTES]
      markdown = GitHub::Markup.render("raw.md", text.force_encoding("utf-8").scrub!, options: { commonmarker_opts: commonmarker_opts })
      GitHub::Goomba::SimplePipeline.to_html(markdown)

    else
      deliver_error! 400,
                     message: "Invalid rendering mode",
                     documentation_url: "/v3/markdown/"
    end
  end

  def deliver_too_large_error!
    deliver_error! 403,
                   message: "This API renders Markdown text up to 400 KB in size. "\
                            "The requested text is too large to render via the API.",
                   errors: [api_error(:Markdown, :data, :too_large)],
                   documentation_url: "/v3/markdown/"
  end
end
