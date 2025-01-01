# typed: true
# frozen_string_literal: true

class Stafftools::PurgatoryController < StafftoolsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:detach_status]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:purge_status]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:restore_status]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    only: [:restore_partial]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:detach_status, :restore_status, :purge_status],
    optional: true

  def restore # rubocop:todo GitHub/UseRestfulActions
    repo = Repositories::Public.find_deleted!(params[:id])
    if params[:lock] == "true"
      repo.lock_excluding_descendants!(Repository::LockDependency::MIGRATING)
    end

    can_restore = Repository.can_restore?(repo)

    if can_restore
      Repository.restore(repo.id, actor: current_user, synchronous: false)
    end
    respond_to do |format|
      format.html do
        if request.xhr?
          if can_restore
            render partial: "stafftools/purgatory/restoring", locals: { repo_id: params[:id] }
          else
            render partial: "stafftools/purgatory/errors", locals: { errors: repo.errors.first&.message }
          end
        else
          redirect_to :back
        end
      end
    end
  end

  def restore_bulk # rubocop:todo GitHub/UseRestfulActions
    return render status: 422, json: { error: "no ids given" } unless params[:ids].is_a?(Array)

    repo_ids = params[:ids].map(&:to_i)

    repos = repo_ids.map { |id| Repositories::Public.find_deleted!(id) }
    errors = {}
    repos.each do |repo|
      can_restore = Repository.can_restore?(repo)
      errors[repo.id] = can_restore ? "" : repo.errors.first.message
    end

    repo_ids = repo_ids.select { |id| errors[id].blank? }
    if repo_ids.any?
      JobStatus.create(id: BulkRepositoryRestoreJob.job_id(repo_ids))
      BulkRepositoryRestoreJob.perform_later(repo_ids, current_user.id)

      respond_to do |format|
        format.json { render json: { errors:, job: { url: job_status_url(BulkRepositoryRestoreJob.job_id(repo_ids)) } } }
      end
    else
      respond_to do |format|
        format.json { render json: { errors: } }
      end
    end
  end

  def restore_partial # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "stafftools/purgatory/restoring", locals: { repo_id: params[:id] }
      end
    end
  end

  def purge # rubocop:todo GitHub/UseRestfulActions
    repo = Repositories::Public.get_active_or_deleted!(params[:id])

    orchestration = RepositoryOrchestration.purge(repo)
    orchestration.execute

    respond_to do |format|
      format.html do
        if request.xhr?
          render partial: "stafftools/purgatory/purging", locals: { repo_id: params[:id] }
        else
          redirect_to :back
        end
      end
    end
  end

  def detach # rubocop:todo GitHub/UseRestfulActions
    repo = Repositories::Public.find_deleted(params[:id].to_i)
    return render_404 unless repo

    repo.detach!

    respond_to do |format|
      format.html do
        if request.xhr?
          render partial: "stafftools/purgatory/detaching", locals: { repo_id: params[:id] }
        else
          redirect_to :back
        end
      end
    end
  end

  def detach_status # rubocop:todo GitHub/UseRestfulActions
    repo_id = params[:id].to_i
    orchestration = DetachRepositoryOrchestration.where(repository_id: repo_id).last
    msg = orchestration&.state || "Not created"
    render html: msg, status: status
  end

  def restore_status # rubocop:todo GitHub/UseRestfulActions
    status = Restoration::RepositoryRestoreStatus.for(repository_id: params[:id])
    render html: status.safe_message, status: status.status
    status.reset_message_if_finished
  end

  def purge_status # rubocop:todo GitHub/UseRestfulActions
    id = params[:id].to_i
    orchestration = PurgeRepositoryOrchestration.where(repository_id: id).first

    http = :accepted
    msg = "Not created"
    if orchestration.present?
      msg = case orchestration.state.to_sym
      when :created
        "Queued..."
      when :started, :running
        "Purging data..."
      when :succeeded, :skipped
        http = :ok
        "Done!"
      when :failed
        http = :ok
        "Failed"
      else
        "Unknown: #{orchestration.state}"
      end
    end

    render html: msg, status: http
  end
end
