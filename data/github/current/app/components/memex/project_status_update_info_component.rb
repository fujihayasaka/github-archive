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

  # update_id represents the ID of a specific status update to display. If nil, the latest status update will be used.
  def initialize(project:, owner:, update_id: nil)
    @project = project
    @owner = owner
    @update_id = update_id
  end

  memoize def project_status_update
    @update_id ? @project.memex_project_statuses.find_by(id: @update_id) : @project.latest_status_update
  end

  memoize def parsed_status_update
    return {} unless project_status_update.present?

    status_info = JSON.parse(project_status_update.status_value)

    status_option = find_status_option(status_info["status_id"])

    {
      id: project_status_update.id,
      status: status_option && status_option[:nameHtml],
      color_code: status_option && COLOR_CODES.fetch(status_option[:color].to_sym),
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
end
