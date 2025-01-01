# typed: true
# frozen_string_literal: true

class UserReviewedFilesController < AbstractRepositoryController
  include PullRequests::DatabaseSelection

  before_action :login_required
  before_action :load_current_pull_request

  prepend_around_action :use_repository_cluster_replicas, only: [:create], if: :use_repos_replica_for_create?

  def create
    reviewed_file = current_user.reviewed_files.new(filepath: params[:path], pull_request_id: @pull.id, head_sha: @pull.head_sha)

    begin
      reviewed_file.save!
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => error
      if record_not_unique?(error)
        reviewed_file = current_user.reviewed_files.for(@pull).find_by!(filepath: params[:path])
        reviewed_file.update_attribute(:dismissed, false)
      end
    end

    GlobalInstrumenter.instrument("pull_request_file.viewed", {
      repository: @pull.repository,
      pull_request: @pull,
      actor: current_user,
      file_path: params[:path],
      action: "VIEWED",
    })

    view_model_params = {
      pull_request: @pull,
      path: params[:path],
      user: current_user,
    }

    # If this reviewed file record isn't valid, the user marked a file that no
    # longer exists as viewed and we're not persisting that. This will override
    # the checkbox so it still appears checked to them.
    unless reviewed_file.valid?
      view_model_params[:reviewed] = true
    end

    respond_to do |format|
      format.html do
        if request.xhr?
          render partial: "diff/file_review", locals: {
            view: create_view_model(Diff::FileReviewView, view_model_params)
          }
        else
          redirect_to :back
        end
      end
    end
  end

  def destroy
    reviewed_file = current_user.reviewed_files.for(@pull).find_by(filepath: params[:path])
    return render_404 unless reviewed_file
    reviewed_file.destroy

    GlobalInstrumenter.instrument("pull_request_file.unviewed", {
      repository: @pull.repository,
      pull_request: @pull,
      actor: current_user,
      file_path: params[:path],
      action: "UNVIEWED",
    })

    respond_to do |format|
      format.html do
        if request.xhr?
          render partial: "diff/file_review", locals: {
            view: create_view_model(Diff::FileReviewView,
              pull_request: @pull,
              path: params[:path],
              user: current_user
            )
          }
        else
          redirect_to :back
        end
      end
    end
  end

  private

  def load_current_pull_request
    @pull = current_repository.issues.find_by_number(params[:pull_id].to_i).try(:pull_request)
    return render_404 unless @pull
  end

  def route_supports_advisory_workspaces?
    true
  end

  def record_not_unique?(error)
    case error
    when ActiveRecord::RecordNotUnique
      true
    when ActiveRecord::RecordInvalid
      error.record.errors.map(&:type).include?(:taken)
    else
      false
    end
  end

  def use_repository_cluster_replicas(&block)
    use_replica_clusters([ApplicationRecord::Repositories], &block)
  end

  def use_repos_replica_for_create?
    GitHub.flipper[:use_repos_replica_for_user_reviewed_files_create].enabled?
  end
end
