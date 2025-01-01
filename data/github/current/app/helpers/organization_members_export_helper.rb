# typed: true
# frozen_string_literal: true

# Shared logic for exporting org members in controllers
module OrganizationMembersExportHelper
  extend T::Helpers
  requires_ancestor { ApplicationController }

  def render_org_member_export(export)
    return render_404 unless export.exists?
    storage = export.storage

    GitHub.dogstats.increment("organization_members_export", tags: ["action:download"])

    response.headers["Content-Type"] = export.content_type
    response.headers["Content-Length"] = storage.size.to_s
    response.headers["Content-Disposition"] = "attachment; filename=\"#{export.human_filename}\""
    response.headers["Last-Modified"] = export.created_at.ctime
    self.response_body = Enumerator.new do |output|
      storage.get do |chunk|
        output << chunk
      end
    end
  end

  def respond_with_org_member_export(export:, export_url:, verify_url: nil)
    respond_to do |format|
      format.json do
        if export.persisted?
          body = {
            export_url: export_url,
            job_url: job_status_url(export),
          }
          body[:verify_url] = verify_url unless verify_url.nil?

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
end
