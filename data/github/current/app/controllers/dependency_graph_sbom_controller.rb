# typed: true
# frozen_string_literal: true

class DependencyGraphSBOMController < AbstractRepositoryController
  before_action :check_feature_is_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    only: [:show, :signed_download]

  def show
    if async_sbom_enabled? && params[:sbom_uuid].present?
      show_async
    else
      show_sync
    end
  end

  def signed_download # rubocop:disable GitHub/UseRestfulActions
    return render_404 unless async_sbom_enabled? && params[:sbom_uuid].present?

    sbom_uuid = params[:sbom_uuid]

    report_manager = DependencyGraph::SBOM::ReportManager.new(repo: current_repository, user: current_user)
    result = report_manager.fetch_sbom(sbom_uuid:)

    if result.status == :JOB_STATUS_COMPLETED
      redirect_to result.sbom_url
    else
      # If the download isn't ready, or there's an error, return to the show view to handle it.
      redirect_to dependency_graph_fetch_sbom_path(sbom_uuid:)
    end
  rescue DependencyGraph::SBOM::SBOMNotFoundError
    render_404
  rescue DependencyGraph::SBOM::SBOMRequestError => e
    Failbot.report(e, app: "github-dependency-graph")
    flash[:error] = "We encountered a problem with your request. Please try again. If the problem persists, please contact support."
    redirect_to dependency_graph_fetch_sbom_path(sbom_uuid:)
  rescue DependencyGraph::SBOM::SBOMTimeoutError => e
    Failbot.report(e, app: "github-dependency-graph")
    flash[:error] = "We couldn't complete your request in time. Please try again. If the problem persists, please contact support."
    redirect_to dependency_graph_fetch_sbom_path(sbom_uuid:)
  end

  def create
    return render_404 unless async_sbom_enabled?

    report_manager = DependencyGraph::SBOM::ReportManager.new(repo: current_repository, user: current_user)
    sbom_uuid = report_manager.generate_sbom

    redirect_to dependency_graph_fetch_sbom_path(sbom_uuid:)
  rescue DependencyGraph::SBOM::SBOMRequestError => e
    Failbot.report(e, app: "github-dependency-graph")
    flash[:error] = "We encountered a problem generating the SBOM. Please try again. If the problem persists, please contact support."
    redirect_to network_dependencies_path
  rescue DependencyGraph::SBOM::SBOMTimeoutError => e
    Failbot.report(e, app: "github-dependency-graph")
    flash[:error] = "We couldn't complete your request in time. Please try again. If the problem persists, please contact support."
    redirect_to network_dependencies_path
  end

  private

  def show_sync
    payload = nil
    filename = nil

    begin
      sbom_file = DependencyGraph::SBOM.get_sbom_for_repository(current_repository, ghes: GitHub.enterprise?)
      payload = sbom_file.contents
      filename = sbom_file.filename
    rescue DependencyGraph::SBOM::SBOMRequestError => e
      Failbot.report(e, app: "github-dependency-graph")
      flash[:error] = "We encountered a problem with your request. Please try again. If the problem persists, please contact support."
      return redirect_to network_dependencies_path
    rescue DependencyGraph::SBOM::SBOMTimeoutError => e
      Failbot.report(e, app: "github-dependency-graph")
      flash[:error] = "We couldn't complete your request in time. Please try again. If the problem persists, please contact support."
      return redirect_to network_dependencies_path
    end

    send_data(
      payload,
      type: :json,
      filename: filename
    )
  end

  def show_async
    sbom_uuid = params[:sbom_uuid]

    respond_to do |format|
      format.html do
        render "dependency_graph_sbom/show", locals: {
          sbom_uuid:,
          repository: current_repository,
          poll_url: dependency_graph_fetch_sbom_path(sbom_uuid:),
        }
      end

      format.html_fragment do
        begin
          report_manager = DependencyGraph::SBOM::ReportManager.new(repo: current_repository, user: current_user)
          result = report_manager.poll_sbom_readiness(sbom_uuid:)

          case result.status
          when :JOB_STATUS_COMPLETED
            # If the status is complete, render a download button that routes to #signed_download
            render partial: "dependency_graph_sbom/complete", formats: [:html], locals: {
              download_url: dependency_graph_download_sbom_path(sbom_uuid:),
              repository: current_repository,
            }
          when :JOB_STATUS_FAILED, :JOB_STATUS_BLOCKED
            # This outcome represents a user-visible background job failure so we should report this as an error.
            Failbot.report(
              DependencyGraph::SBOM::SBOMRequestError.new(result.user_error_message || "SBOM generation failed"),
              app: "github-dependency-graph",
            )
            render partial: "dependency_graph_sbom/error", formats: [:html], locals: {
              repository: current_repository,
            }
          else
            head 202
          end
        rescue DependencyGraph::SBOM::SBOMNotFoundError
          render partial: "dependency_graph_sbom/not_found", formats: [:html], locals: {
            repository: current_repository,
          }
        rescue DependencyGraph::SBOM::SBOMRequestError => e
          Failbot.report(e, app: "github-dependency-graph")
          render partial: "dependency_graph_sbom/error", formats: [:html], locals: {
            repository: current_repository,
          }
        rescue DependencyGraph::SBOM::SBOMTimeoutError
          head 202
        end
      end
    end
  end

  # This feature is only available in cloud until we ship DGP in GHES
  def async_sbom_enabled?
    !GitHub.enterprise?
  end

  def check_feature_is_enabled
    render_404 unless current_repository.dependency_graph_enabled?
  end
end
