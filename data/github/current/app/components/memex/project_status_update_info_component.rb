# typed: true
# frozen_string_literal: true

require "json"

class Memex::ProjectStatusUpdateInfoComponent < ApplicationComponent
  COLOR_CODES = {
    BLUE: :accent,
    GREEN: :success,
    YELLOW: :attention,
    ORANGE: :severe,
    RED: :danger,
    PINK: :sponsors,
    PURPLE: :done,
    GRAY: :default
  }.freeze

  def initialize(project:, owner:)
    @project = project
    @owner = owner
  end

  memoize def latest_project_status_update
    @project.latest_status_update
  end

  memoize def parsed_status_update
    return {} unless latest_project_status_update.present?

    status_info = JSON.parse(latest_project_status_update.status_value)

    status_option = find_status_option(status_info["status_id"])

    {
      id: latest_project_status_update.id,
      status: status_option && status_option[:nameHtml],
      color_code: status_option && COLOR_CODES.fetch(status_option[:color].to_sym),
      start_date: format_date(status_info["start_date"]),
      target_date: format_date(status_info["target_date"]),
    }
  end

  memoize def status_update_path
    case @owner
    when Organization
      show_org_memex_path(@owner, @project.number, pane: "info", statusUpdateId: parsed_status_update[:id])
    when User
      show_user_memex_path(@owner, @project.number, pane: "info", statusUpdateId: parsed_status_update[:id])
    end
  end

  def find_status_option(status_id)
    return nil unless status_id.present?

    MemexProjectStatus::STATUS_OPTIONS[status_id]
  end

  def format_date(date_string)
    return nil unless date_string.present?

    Date.parse(date_string).strftime("%b %d, %Y")
  end
end
