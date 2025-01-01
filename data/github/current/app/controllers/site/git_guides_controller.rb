# typed: true
# frozen_string_literal: true

class Site::GitGuidesController < Site::BaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index, :show]

  layout "site"

  stylesheet_bundle "git-guides"

  def index
    render "site/git_guides/index"
  end

  def show
    sanitized_id = helpers.sanitize_filename(params[:id])
    raw_file_path = File.join(GitHub::AppEnvironment.root, "app/views", "site/git_guides/md/_#{sanitized_id}.text.raw")

    if File.exist?(raw_file_path) && File.readable?(raw_file_path)
      title = sanitized_id.gsub(/-/, " ")
      description = "Learn about when and how to use #{title}."
      description = "Learn how to #{title}." if !(/\Agit/i).match?(sanitized_id)
      markdown = File.read(raw_file_path)

      render "site/git_guides/show", locals: { id: sanitized_id, title: title, description: description, markdown: markdown }
    else
      render_404
    end
  end
end
