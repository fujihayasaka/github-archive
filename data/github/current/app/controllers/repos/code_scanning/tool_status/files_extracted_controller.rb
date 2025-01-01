# typed: true
# frozen_string_literal: true

class Repos::CodeScanning::ToolStatus::FilesExtractedController < Repos::CodeScanning::ToolStatus::AbstractController
  include ScanningControllerMethods

  before_action :login_required,
    :check_code_scanning_read,
    :default_branch_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Notify,
    only: [:show]

  track_latency_slo "p99-ui-request", 3000, only: [:show]
  track_latency_slo "p50-ui-request", 750, only: [:show]

  def show
    respond_to do |format|
      format.html do
        return render_partial if request.xhr?
        redirect_to repository_code_scanning_results_tool_status_show_path(tool_name: params[:tool_name])
      end
      format.csv { generate_csv }
    end
  end

  private

  def ids
    return [] unless params[:ids].present?
    return [] unless params[:ids].is_a?(Array)
    params[:ids].map(&:to_i)
  end

  def generate_csv
    response = GitHub::Turboscan.get_files_extracted(
      repository_id: current_repository.id,
      ref: current_repository.default_branch_ref.qualified_name,
      tool: params[:tool_name],
      analysis_ids: ids,
    )

    return render_404 if response.nil?
    raise StandardError.new(response.error) if response.error.present?

    data = CSV.generate do |csv|
      csv << ["Configuration", "Language", "File Path", "Successfully Extracted", "Failure Reason"]
      response.data&.categories&.each do |category_name, category_files|
        category_files.languages.each do |language, language_files|
          language_files.files.each do |file|
            csv << [category_name, language, file.path.dup.force_encoding(Encoding::UTF_8).scrub!, file.success, file.message]
          end
        end
      end
    end

    send_data data, filename: "code-scanning-files-extracted.csv"
  end

  def render_partial
    response = GitHub::Turboscan.get_files_extracted_summary(
      repository_id: current_repository.id,
      ref: current_repository.default_branch_ref.qualified_name,
      tool: params[:tool_name],
    )

    return render_404 if response.nil? || (response.error.nil? && response.data.nil?)
    raise StandardError.new(response.error) if response.error.present?

    render partial: "repos/code_scanning/tool_status/files_extracted/show", locals: {
      current_repository: current_repository,
      tool_name: params[:tool_name],
      languages_extracted: T.must(response.data).languages_extracted.to_a.sort_by { |language, _| language },
    }
  end
end
