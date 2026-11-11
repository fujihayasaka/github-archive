# typed: strict
# frozen_string_literal: true

class Stafftools::EnterpriseAgreements::ListItemComponent < ApplicationComponent
  VssEventCounts = T.type_alias { { assign: Integer, revoke: Integer, other: Integer } }

  sig do
    params(
      business: Business,
      enterprise_agreement: Licensing::EnterpriseAgreement,
      billable_licenses: T.nilable(Integer),
      non_linked_licenses: T.nilable(Integer),
      vss_subscription_events: T.nilable(VssEventCounts)
    ).void
  end
  def initialize(business:, enterprise_agreement:, billable_licenses: 0, non_linked_licenses: 0, vss_subscription_events: nil)
    @business = T.let(business, ::Business)
    @enterprise_agreement = T.let(enterprise_agreement, Licensing::EnterpriseAgreement)
    @billable_licenses = T.let(billable_licenses || 0, Integer)
    @non_linked_licenses = T.let(non_linked_licenses || 0, Integer)
    @vss_event_counts = T.let(vss_subscription_events || { assign: 0, revoke: 0, other: 0 }, VssEventCounts)
  end

  sig { returns(T::Boolean) }
  def render?
    !GitHub.enterprise?
  end

  sig { returns(Integer) }
  def events_count
    @vss_event_counts[:assign] + @vss_event_counts[:revoke] + @vss_event_counts[:other]
  end

  sig { returns(Integer) }
  def assign_events_count
    @vss_event_counts[:assign]
  end

  sig { returns(Integer) }
  def remove_events_count
    @vss_event_counts[:revoke]
  end

  sig { returns(Integer) }
  def other_events_count
    @vss_event_counts[:other]
  end

  sig { returns(T::Boolean) }
  def has_events?
    events_count > 0
  end

  sig { returns(T::Boolean) }
  def show_events_action?
    @enterprise_agreement.visual_studio_bundle?
  end

  sig { returns(String) }
  def events_dialog_id
    "vss-events-dialog-#{@enterprise_agreement.id}"
  end

  sig { returns(String) }
  def backfill_dialog_id
    "backfill-enterprise-agreement-#{@enterprise_agreement.id}"
  end
end
