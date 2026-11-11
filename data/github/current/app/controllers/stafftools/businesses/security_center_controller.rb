# typed: true
# frozen_string_literal: true

require "github/security_center/logging_helper"

class Stafftools::Businesses::SecurityCenterController < Stafftools::Businesses::BusinessBaseController
  include GitHub::SecurityCenter::LoggingHelper

  Initialization = ::SecurityOverviewAnalytics::Initialization
  EntityType = ::SecurityCenter::Serializers::BusinessReconciliationJobEntityType::EntityType

  before_action :dotcom_required # limiting to dotcom so only GitHub staff can access

  around_action :set_log_context

  layout "layouts/stafftools/business"

  def show
    render "stafftools/businesses/security_center", locals: {
      business: this_business,
      analytics_eligible: ::SecurityOverviewAnalytics::TenantValidationHelper.is_owner_in_scope?(this_business)
    }
  end

  def trigger_reconciliation_job # rubocop:todo GitHub/UseRestfulActions
    entity_type_param = params[:entity_type]

    case entity_type_param
    when "org"
      source_event = "security_center.stafftools.reconciliation.business.organizations"
      entity_type = EntityType::Organization
    when "user"
      source_event = "security_center.stafftools.reconciliation.business.users"
      entity_type = EntityType::User
    else
      raise "Invalid entity type: #{entity_type_param}"
    end

    SecurityCenter::BusinessReconciliationJob.perform_later(business_id: this_business.id, source_event: source_event, entity_type: entity_type)
    GitHub.logger.info(
      "Queued business reconciliation job from stafftools for #{entity_type} entities",
      "code.namespace": self.class.name,
      "code.function": __method__,
      "gh.security_center.source_event": source_event,
    )

    redirect_to stafftools_enterprise_security_center_path(this_business), flash: { notice: "Reconciliation job scheduled." }
  end

  def initialize_analytics # rubocop:todo GitHub/UseRestfulActions
    feature_type = params[:type]

    if feature_type.nil?
      ::SecurityOverviewAnalytics::FanoutScheduler.initialize_for(this_business)
      Initialization.for(this_business).enqueue(type: nil)
    else
      type = Initialization::Type.try_deserialize(feature_type)
      Initialization.for(this_business).enqueue(type:)
    end

    log_info(
      "Queued analytics initialization job from stafftools",
      "gh.security_overview_analytics.initialization_type": feature_type || "all"
    )
    redirect_to stafftools_enterprise_security_center_path(this_business), flash: { notice: "Analytics initialization scheduled." }
  end

  def reset_analytics # rubocop:todo GitHub/UseRestfulActions
    type = params[:type] ? Initialization::Type.deserialize(params[:type]) : nil
    Initialization::BatchedResetJob.perform_later(business_ids: [this_business.id], include_private_beta: true, type: type&.serialize)

    log_info(
      "Queued analytics reset job from stafftools",
      "gh.security_overview_analytics.initialization_type": type&.serialize || "all",
    )

    redirect_to stafftools_enterprise_security_center_path(this_business), flash: { notice: "Analytics reset scheduled." }
  end

  def enqueue_analytics_reconciliation # rubocop:todo GitHub/UseRestfulActions
    ::SecurityOverviewAnalytics::FanoutScheduler.reconcile_for(this_business)

    SecurityOverviewAnalytics::Reconciliation::BusinessReconciliationJob.perform_later(business_id: this_business.id)
    SecurityOverviewAnalytics::Reconciliation::BusinessReconciliationJob.perform_later(
      business_id: this_business.id,
      entity_type: SecurityCenter::Serializers::BusinessReconciliationJobEntityType::EntityType::User
    )

    log_info(
      "Queued analytics reconciliation job from stafftools",
      "gh.security_overview_analytics.initialization_type": "all",
    )
    redirect_to stafftools_enterprise_security_center_path(this_business), flash: { notice: "Scheduled analytics reconciliation." }
  end

  private

  def set_log_context
    GitHub.logger.with_named_tags(
      "enduser.id": current_user.display_login,
      "gh.enduser.id": current_user.id,
      "gh.business.id": this_business.id,
      "gh.business.login": this_business.display_login,
    ) do
      yield
    end
  end

  depends_on_clusters \
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters \
    ApplicationRecord::Copilot,
    only: [:show],
    optional: true
end
