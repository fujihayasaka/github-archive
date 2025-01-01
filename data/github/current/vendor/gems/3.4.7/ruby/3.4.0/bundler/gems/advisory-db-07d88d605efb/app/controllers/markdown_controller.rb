# frozen_string_literal: true

class MarkdownController < InboxController
  def preview
    markdown = params[:content]
    html =
      if markdown.blank?
        "<p>Nothing to preview</p>"
      elsif Rails.env.development?
        ::GitHub::Telemetry::Logs.logger.warn("Returning empty markdown preview in local development environment. Markdown rendering will only work with a sideloaded github environment. If you need to test it locally, you will need to comment out this check.")
        "<p>Nothing to preview</p>"
      else
        AdvisoryDB.github.markdown(markdown, mode: "gfm")
      end

    render html: html.html_safe # rubocop:disable Rails/OutputSafety
  end
end
