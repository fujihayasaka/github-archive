# typed: true
# frozen_string_literal: true

require "ghec_admin"

module EnterpriseUsersExportHelper
  include BusinessesHelper
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

  # rubocop:disable GitHub/RailsViewRenderLiteral
  def respond_with_enterprise_users_export(export:, export_url:)
    respond_to do |format|
      format.json do
        if export.persisted?
          body = {
            export_url: export_url,
            notify_when_complete: export.notify_when_complete?,
            job_url: job_status_url(export),
          }
          email = current_user.is_enterprise_managed? ? current_user.profile_email : current_user.email
          msg = "The CSV report is being generated. You'll receive an email at #{email} as soon as it's ready."
          body[:notify] = msg if enterprise_all_members_count > 1000

          render json: body, status: 201
        else
          render nothing: true, status: 400
        end
      end

      format.all do
        render_404
      end
    end
  end

  def report_type
    GHECAdmin::EnterpriseUsersExport.to_s
  end

  def report_name
    "enterprise_users_export"
  end
end
