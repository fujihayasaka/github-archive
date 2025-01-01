# typed: true
# frozen_string_literal: true
class AbuseReportsController < AbstractRepositoryController
  include CommentsHelper

  before_action :login_required
  before_action :ask_the_gatekeeper

  def create
    user_supplied_reason = params[:reason]&.upcase
    possible_reasons = Platform::Enums::AbuseReportReason.values.keys
    sanitized_reason = possible_reasons.include?(user_supplied_reason) ? user_supplied_reason : "UNSPECIFIED"
    reported_content = find_reported_content_from_gid(params.fetch(:comment_id))

    unless reported_content
      flash[:error] = "Content not found"
      redirect_back(fallback_location: "/") and return
    end

    authorization = ContentAuthorizer.authorize(current_user, :report_content, :create, reported_content: reported_content)
    if authorization.failed?
      flash[:error] = authorization.error_messages
      redirect_back(fallback_location: "/") and return
    end

    abuse_report = AbuseReport.create(
      reporting_user: current_user,
      reported_user: reported_content.user,
      reported_content: reported_content,
      repository_id: reported_content.repository,
      reason: sanitized_reason.downcase,
      show_to_maintainer: true,
    )

    if abuse_report.errors&.any?
      flash[:error] = abuse_report.errors.map(&:message).to_sentence
    else
      flash[:notice] = "Your report has been submitted for review."
    end

    redirect_back(fallback_location: "/")
  end

  def resolve_abuse_reports # rubocop:todo GitHub/UseRestfulActions
    return render_404 if params[:type] == "GistComment" || params[:type] == "Gist"

    if AbuseReport.mark_resolved_for_content(current_user, params[:type], params[:id])
      flash[:notice] = "Report marked as resolved"
    else
      flash[:error] = "You cannot perform that action at this time."
    end

    if request.xhr?
      respond_to do |format|
        format.html do
          render Repositories::UnderlineNavComponent.new(
            repository: current_repository,
            selected_link: :tiered_reporting,
            display_variant: :padded,
            user_can_write_wiki: current_user_can_write_wiki?
          ), layout: false
        end
      end
    else
      redirect_to reported_content_path(resolved_filter: params[:resolved_filter])
    end
  end

  def unresolve_abuse_reports # rubocop:todo GitHub/UseRestfulActions
    return render_404 if params[:type] == "GistComment" || params[:type] == "Gist"

    if AbuseReport.mark_unresolved_for_content(current_user, params[:type], params[:id])
      flash[:notice] = "Report marked as unresolved"
    else
      flash[:error] = "You cannot perform that action at this time."
    end

    if request.xhr?
      respond_to do |format|
        format.html do
          render Repositories::UnderlineNavComponent.new(
            repository: current_repository,
            selected_link: :tiered_reporting,
            display_variant: :padded,
            user_can_write_wiki: current_user_can_write_wiki?
          ), layout: false
        end
      end
    else
      redirect_to reported_content_path(resolved_filter: params[:resolved_filter])
    end
  end

  private

  def find_reported_content_from_gid(gid)
    type, id = Platform::Helpers::NodeIdentification.from_global_id(gid)
    klass = type.constantize
    return klass.find(id) if klass.method_defined?(:abuse_reports)
  rescue Platform::Errors::NotFound
  end
end
