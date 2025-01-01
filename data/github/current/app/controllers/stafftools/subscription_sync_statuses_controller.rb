# typed: true
# frozen_string_literal: true

class Stafftools::SubscriptionSyncStatusesController < StafftoolsController
  include StafftoolsHelper
  before_action :ensure_billing_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  PER_PAGE = 100

  def index
    @unsuccessful_sync_statuses = Billing::SubscriptionSyncStatus.unsuccessful
      .ignoring_recent
      .or(Billing::SubscriptionSyncStatus.under_investigation)
      .paginate(page: params[:page], per_page: PER_PAGE)
      .order(updated_at: :desc)

    render "stafftools/subscription_sync_statuses/index", locals: { unsuccessful_sync_statuses: @unsuccessful_sync_statuses }
  end

  def show
    sync_status = Billing::SubscriptionSyncStatus.find(params[:id])
    audit_query = stafftools_audit_log_query(sync_status.target)
    audit_query << if GitHub.driftwood_ade_queries_enabled?
      " and action == 'plan_subscription.synchronize'"
    else
      " AND action:plan_subscription.synchronize"
    end

    es_query = Audit::Driftwood::Query.new_stafftools_query(
      phrase: audit_query,
      current_user: current_user,
      per_page: 2,
    )
    results = es_query.execute
    logs = AuditLogEntry.new_from_array(results)

    render partial: "stafftools/subscription_sync_statuses/show", locals: {
      sync_status: sync_status,
      audit_query: audit_query,
      audit_results: results,
      audit_logs: logs
    }
  end

  def force_sync # rubocop:todo GitHub/UseRestfulActions
    @sync_status = ::Billing::SubscriptionSyncStatus.find(params[:subscription_sync_status_id])
    @sync_status.target.create_or_update_external_subscription!(force: true)
    flash[:notice] = "Forced subscription sync queued for #{@sync_status.target.name}"
  rescue StandardError => e # rubocop:todo Lint/GenericRescue
    flash[:error] = e
  ensure
    redirect_back(fallback_location: "stafftools/subscription_sync_statuses")
  end

  def bulk_force_sync # rubocop:todo GitHub/UseRestfulActions
    failed_sync_status = Billing::SubscriptionSyncStatus.failure
      .ignoring_recent
      .or(Billing::SubscriptionSyncStatus.under_investigation)

    failed_sync_status.each do |sync_status|
      sync_status.target.create_or_update_external_subscription!(force: true)
    end
    flash[:notice] = "Forced subscription sync queued for #{failed_sync_status.count} users"
    rescue StandardError => e # rubocop:todo Lint/GenericRescue
      flash[:error] = e
    ensure
      redirect_back(fallback_location: "stafftools/subscription_sync_statuses")
  end

  def mark_successful # rubocop:todo GitHub/UseRestfulActions
    @sync_status = ::Billing::SubscriptionSyncStatus.find(params[:subscription_sync_status_id])
    @sync_status.succeed!
    flash[:notice] = "SubscriptionSyncStatus id #{@sync_status.id} (for #{@sync_status.target.name}) manually marked as successful."
  rescue ActiveRecord::RecordNotFound
    flash[:error] = "SubscriptionSyncStatus id #{params[:subscription_sync_status_id]} not found"
  ensure
    redirect_back(fallback_location: "stafftools/subscription_sync_statuses")
  end

  def investigate # rubocop:todo GitHub/UseRestfulActions
    sync_status = ::Billing::SubscriptionSyncStatus.find(params[:id])

    if sync_status.update(external_sync_status: :under_investigation, investigation_notes: params[:investigation_notes])
      flash[:notice] = "Successfully marked sync as under investigation"
    else
      flash[:error] = "There was an error marking the sync as under investigation (#{sync_status.errors.full_messages.to_sentence})"
    end

    redirect_to stafftools_subscription_sync_statuses_path
  end
end
