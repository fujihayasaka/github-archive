# typed: true
# frozen_string_literal: true

class Stafftools::Users::SearchRecords::BackfillsController < StafftoolsController
  include Stafftools::Users::SearchRecords::BackfillJob

  DEFAULT_BACKFILL_WORKERS = 1
  MAX_BACKFILL_WORKERS = Stafftools::User::SearchView::MAX_BACKFILL_WORKERS
  SUPPORTED_OPERATIONS = %w(start pause reset update_workers clear).freeze

  before_action :ensure_org_not_user
  before_action :ensure_user_exists
  before_action :ensure_feature_enabled

  def create
    unless BACKFILL_TYPES.key?(backfill_type.to_sym)
      return redirect_with_error("Unknown backfill type: #{backfill_type.inspect}")
    end

    unless SUPPORTED_OPERATIONS.include?(operation)
      return redirect_with_error("Unknown backfill operation: #{operation.inspect}")
    end

    case operation
    when "start" then start_backfill
    when "pause" then pause_backfill
    when "reset" then reset_backfill
    when "update_workers" then update_workers_backfill
    when "clear" then clear_backfill
    end
  end

  private

  def backfill_type
    params[:backfill_type].to_s
  end

  def operation
    params[:operation].to_s
  end

  def ensure_feature_enabled
    render_404 unless FeatureFlag.vexi.enabled?(:elasticsearch_organization_reindex, current_user, default: false)
  end

  def start_backfill
    workers = parsed_workers
    return if workers.nil?

    repair_job = create_backfill_job(backfill_type)
    repair_job.reset!
    repair_job.enable
    repair_job.start(workers)

    redirect_to stafftools_user_search_record_path(this_user), notice: start_backfill_notice(backfill_type, workers)
  rescue Elastomer::RepairJob::InvalidRepairScopeError => e
    redirect_to stafftools_user_search_record_path(this_user), flash: { error: e.message }
  end

  def pause_backfill
    create_backfill_job(backfill_type).pause

    redirect_to stafftools_user_search_record_path(this_user), notice: pause_backfill_notice(backfill_type)
  end

  def reset_backfill
    create_backfill_job(backfill_type).reset!

    redirect_to stafftools_user_search_record_path(this_user), notice: reset_backfill_notice(backfill_type)
  end

  def update_workers_backfill
    workers = parsed_workers
    return if workers.nil?

    repair_job = create_backfill_job(backfill_type)
    unless repair_job.exists?
      return redirect_with_error("No #{backfill_label(backfill_type)} backfill is currently in progress")
    end

    repair_job.enable
    repair_job.start(workers)

    redirect_to stafftools_user_search_record_path(this_user),
      notice: update_workers_backfill_notice(backfill_type, workers)
  rescue Elastomer::RepairJob::InvalidRepairScopeError => e
    redirect_to stafftools_user_search_record_path(this_user), flash: { error: e.message }
  end

  def clear_backfill
    repair_job = create_backfill_job(backfill_type)
    unless repair_job.exists?
      return redirect_with_error("No #{backfill_label(backfill_type)} backfill to clear")
    end

    unless repair_job.finished?
      return redirect_with_error("#{backfill_label(backfill_type)} backfill is not finished and cannot be cleared. Pause and reset it instead.")
    end

    repair_job.reset!

    redirect_to stafftools_user_search_record_path(this_user),
      notice: clear_backfill_notice(backfill_type)
  end

  def parsed_workers
    workers = params.fetch("workers", DEFAULT_BACKFILL_WORKERS).to_i
    return workers if workers.between?(1, MAX_BACKFILL_WORKERS)

    redirect_with_error("Worker count must be between 1 and #{MAX_BACKFILL_WORKERS}")
    nil
  end

  def redirect_with_error(message)
    redirect_to stafftools_user_search_record_path(this_user), flash: { error: message }
  end
end
