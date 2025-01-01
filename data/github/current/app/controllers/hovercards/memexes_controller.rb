# typed: true
# frozen_string_literal: true

class Hovercards::MemexesController < Memexes::Controller
  include GitHub::Memoizer

  before_action :require_xhr, only: [:show]
  before_action :require_this_memex, only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Memex,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:show]

  def show
    return render_404 unless this_memex&.readable_by?(current_user)

    render "hovercards/memexes/show", locals: {
      project: this_memex,
      title:,
      icon:,
      title_sub_text:,
      this_status:,
    }, layout: false
  end

  private

  memoize def this_view
    # When a status update is deep-linked, ensure we don't showcase a view
    return nil if params[:statusUpdateId]
    this_memex.memex_project_views&.find_by(number: params[:view])
  end

  memoize def this_status
    params[:statusUpdateId] ? this_memex.memex_project_statuses.find_by(id: params[:statusUpdateId]) : this_memex.latest_status_update
  end

  def title
    this_view ? this_view.name : this_memex.title_html
  end

  def title_sub_text
    return unless this_view

    this_memex.title
  end

  def icon
    layout_icon_map[this_view&.layout] || "table"
  end

  def layout_icon_map
    {
      "table_layout" => "table",
      "board_layout" => "project",
      "roadmap_layout" => "project-roadmap",
    }
  end

  def require_this_memex
    render_404 unless this_memex
  end
end
