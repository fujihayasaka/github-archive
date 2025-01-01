# typed: true
# frozen_string_literal: true

require "ghec_admin"

module DormantUsersExportHelper
  extend T::Helpers
  requires_ancestor { ApplicationController }

  def render_export(export:, stat_name:)
    report = export.report
    return render_404 unless report.exists?
    storage = report.storage

    GitHub.dogstats.increment(stat_name, tags: ["action:download"])

    response.headers["Content-Type"] = report.content_type
    response.headers["Content-Length"] = storage.size.to_s
    response.headers["Content-Disposition"] = "attachment; filename=\"#{report.human_filename}\""
    response.headers["Last-Modified"] = export.created_at.ctime
    self.response_body = Enumerator.new do |output|
      storage.get do |chunk|
        output << chunk
      end
    end
  end

  def report_type
    GHECAdmin::EnterpriseDormantUsersExport.to_s
  end
end
