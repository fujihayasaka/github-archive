# frozen_string_literal: true

class CheckComponent < ApplicationComponent
  def initialize(check:)
    @check = check
    @id = "check-#{SecureRandom.hex(3)}"
  end

  def waiting?
    @check["status"] == "queued" || @check["status"] == "running"
  end

  def message
    @check.values_at("status", "message").compact_blank.join(": ").upcase_first.presence || "Unknown"
  end

  def name
    @check["check_class"].to_s.demodulize.underscore.delete_suffix("_check").humanize
  end

  STATUS_ICON_ARGS = {
    passed: { icon: "check-circle-fill", color: :success, test_selector: "passed-check-icon" },
    failed: { icon: "x-circle-fill", color: :danger, test_selector: "failed-check-icon" },
    warning: { icon: "alert-fill", color: :attention, test_selector: "warning-check-icon" },
    queued: { icon: "dot-fill", color: :attention, test_selector: "queued-check-icon" },
  }.freeze

  def status_icon
    status = @check["status"]
    case status
    when "running"
      RunningCheckIconComponent.new
    else
      args = STATUS_ICON_ARGS[status&.to_sym] || { icon: "dot", color: :muted, test_selector: "blank-check-icon" }
      IconComponent.new(id: @id, mr: 2, **args)
    end
  end
end
