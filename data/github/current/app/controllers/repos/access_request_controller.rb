# typed: true
# frozen_string_literal: true

class Repos::AccessRequestController < AbstractRepositoryController
  include GitHub::Memoizer

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    unless access_request&.active? && access_request.accessible == current_repository
      return render_404
    end

    render "repositories/access_requests/show"
  end

  def consent # rubocop:todo GitHub/UseRestfulActions
    begin
      if params[:consent] == "accept"
        grant = access_request.accept(current_user)
        if grant
          StaffAccessMailer.repo_unlock_request_accepted(grant).deliver_later
          flash[:notice] = "You have successfully granted access to #{current_repository.name_with_display_owner} to GitHub staff until #{grant.expires_at.to_date}."
        end
      end

      if params[:consent] == "deny"
        access_request.deny(current_user)
        StaffAccessMailer.repo_unlock_request_denied(access_request).deliver_later
        flash[:notice] = "You have denied access to #{current_repository.name_with_display_owner} for GitHub staff."
      end
    rescue StaffAccessRequest::InsufficientAbilities
      return render_404
    end

    redirect_to edit_repository_path(current_repository)
  end

  private

  helper_method :access_request
  memoize def access_request
    StaffAccessRequest.find(params[:id])
  end
end
