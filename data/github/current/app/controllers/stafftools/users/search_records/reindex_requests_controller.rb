# typed: true
# frozen_string_literal: true

class Stafftools::Users::SearchRecords::ReindexRequestsController < StafftoolsController
  before_action :ensure_user_exists

  def create
    this_user.calculate_primary_language!
    options = create_params.to_h.symbolize_keys
    if ReindexUserRecordsJob.enabled_for_user?(this_user.id)
      ReindexUserRecordsJob.perform_now(this_user.id, :start, **options)
    else
      Search.add_to_search_index("user", this_user.id)
    end

    redirect_to stafftools_user_search_record_path(this_user), notice: "Reindex job was started."
  end

  def update
    options = update_params.to_h.symbolize_keys
    requested_action = options[:reindex_action]&.to_sym
    unless [:pause, :resume, :reset, :update_workers].include?(requested_action)
      flash[:alert] = "Invalid action: #{options[:reindex_action]}"
      return redirect_to stafftools_user_search_record_path(this_user)
    end
    unless ReindexUserRecordsJob.enabled_for_user?(this_user.id)
      flash[:alert] = "Full reindexing is not enabled for this user."
      return redirect_to stafftools_user_search_record_path(this_user)
    end
    if [:pause, :reset].include?(requested_action)
      ReindexUserRecordsJob.perform_now(this_user.id, requested_action, **options.except(:reindex_action))
    else
      ReindexUserRecordsJob.perform_later(this_user.id, requested_action, **options.except(:reindex_action))
    end
    redirect_to stafftools_user_search_record_path(this_user), notice: "Reindex job was updated."
  end

  private

  def create_params
    params.slice(:workers).permit(workers: {})
  end

  def update_params
    params.slice(:reindex_action, :workers).permit(:reindex_action, workers: {})
  end
end
