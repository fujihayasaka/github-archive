# typed: strict
# frozen_string_literal: true

# Shared logic for exporting business license usage in controllers
module BusinessLicenseConsumptionExportHelper
  extend T::Sig
  extend T::Helpers

  requires_ancestor { ApplicationController::ErrorHandlingDependency }
  requires_ancestor { ApplicationController }

  sig { params(export: Business::LicenseConsumptionExport).void }
  def render_business_license_consumption_export(export)
    return render_404 unless export.remote_object?

    GitHub.dogstats.increment("business_license_consumption_csv_export", tags: ["action:download"])

    response.headers["Content-Type"] = export.content_type
    response.headers["Content-Length"] = export.remote_object.size.to_s
    response.headers["Content-Disposition"] = "attachment; filename=\"#{export.human_filename}\""
    response.headers["Last-Modified"] = export.created_at&.to_time.ctime
    self.response_body = Enumerator.new do |output|
      export.remote_object.get do |chunk|
        output << chunk
      end
    end
  end

  sig { params(export: Business::LicenseConsumptionExport, export_url: String, verify_url: T.nilable(String)).void }
  def respond_with_business_license_consumption_export(export:, export_url:, verify_url: nil)
    respond_to do |format|
      format.json do
        if export.persisted?
          body = {
            export_url: export_url,
            notify_when_complete: export.notify_when_complete?,
            job_url: job_status_url(export),
          }
          body[:verify_url] = verify_url unless verify_url.nil?

          if export.notify_when_complete?
            email = current_user.is_enterprise_managed? ? current_user.profile_email : current_user.email
            body[:notify] = "The CSV report is being generated. You'll receive an email at #{email} as soon as it's ready."
          end

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
