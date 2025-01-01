# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::FlaggedSponsors::FlaggedSponsorFieldComponent < ApplicationComponent
  include AuditLogHelper

  FIELDS = {
    matched_current_client_id: "Client ID",
    matched_historical_client_id: "Historical client ID",
    matched_current_ip: "IP address",
    matched_historical_ip: "Historical IP address",
    matched_current_ip_region_and_user_agent: "IP region and user agent",
  }

  # flagged_record - the FraudFlaggedSponsor record.
  # field - a Symbol that is a key in the FIELDS constant.
  def initialize(flagged_record:, field:)
    @flagged_record  = flagged_record
    @field           = field
  end

  private

  attr_reader :flagged_record, :field

  def render?
    flagged_record.present? && title.present?
  end

  def title
    FIELDS[field]
  end

  def value
    if flagged_record[field].present?
      flagged_record[field]
    else
      "Not matched"
    end
  end

  def value_class
    if flagged_record[field].present?
      "text-mono"
    else
      "text-italic"
    end
  end

  memoize def search_url
    return if flagged_record[field].blank?

    case field
    when :matched_current_ip, :matched_historical_ip
      stafftools_audit_log_path(query: if driftwood_ade_query?(current_user)
                                         "webevents | where actor_ip == '#{value}' and action startswith 'sponsors.'"
                                       else
                                         "actor_ip:#{value} action:sponsors.*"
                                       end)
    when :matched_current_client_id, :matched_historical_client_id
      stafftools_audit_log_path(query: if driftwood_ade_query?(current_user)
                                         "webevents | where data.client_id == '#{value}' and action startswith 'sponsors.'"
                                       else
                                         "data.client_id:#{value} action:sponsors.*"
                                       end)
    end
  end
end
