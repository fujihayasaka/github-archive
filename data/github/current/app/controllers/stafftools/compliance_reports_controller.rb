# typed: true
# frozen_string_literal: true

class Stafftools::ComplianceReportsController < StafftoolsController
  before_action :dotcom_required
  before_action :report_required, only: %i(show edit update destroy)

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    only: [:index, :new, :show, :edit]

  def index
    render "stafftools/compliance_reports/index", locals: { reports: reports }
  end

  def new
    render "stafftools/compliance_reports/new", locals: { report: ComplianceReport.new }
  end

  def create
    report = ComplianceReport.create(params_for_save)

    if report.valid?
      flash[:notice] = "Created #{report.title}."
      redirect_to stafftools_compliance_reports_path
    else
      flash[:error] = "Failed to create report. #{report.errors.full_messages.to_sentence}."
      render "stafftools/compliance_reports/new", locals: { report: report }
    end
  end

  # If it's a download, deliver the blob, otherwise 404.
  def show
    return render_404 unless this_report.download?

    storage = this_report.storage

    response.headers["Content-Type"] = this_report.content_type
    response.headers["Content-Length"] = storage.size.to_s
    response.headers["Content-Disposition"] = "attachment; filename=\"#{this_report.filename}\""
    self.response_body = Enumerator.new do |output|
      storage.get do |chunk|
        output << chunk
      end
    end
  end

  def edit
    render "stafftools/compliance_reports/edit", locals: { report: this_report }
  end

  def update
    this_report.update(params_for_save)

    if this_report.errors.blank?
      flash[:notice] = "Updated #{this_report.title}."
      redirect_to stafftools_compliance_reports_path
    else
      flash[:error] = "Failed to update report. #{this_report.errors.full_messages.to_sentence}."
      render "stafftools/compliance_reports/edit", locals: { report: this_report }
    end
  end

  def destroy
    if this_report.destroy
      flash[:notice] = "Deleted #{this_report.title}."
      redirect_to stafftools_compliance_reports_path
    else
      flash[:error] = "Failed to delete report. #{this_report.errors.full_messages.to_sentence}."
      redirect_to stafftools_compliance_reports_path
    end
  end

  private

  memoize def reports
    ComplianceReport.top_level_reports
  end

  def report_required
    render_404 unless this_report
  end

  memoize def this_report
    ComplianceReport.find_by(slug: params[:slug])
  end

  def compliance_report_params
    params.require(:compliance_report).permit(
      :slug,
      :title,
      :availability,
      :coverage_period,
      :description,
      :report_type,
      :blob,
      :url,
      :parent_id,
      :display_order,
      :published
    )
  end

  def params_for_save
    prepared_params = compliance_report_params
    blob_io = prepared_params.delete(:blob)

    if prepared_params[:report_type] == "download" && blob_io.present?
      filename = blob_io.original_filename
      blob = blob_io.read
      prepared_params.merge!(blob: blob, filename: filename)
    end

    prepared_params
  end
end
