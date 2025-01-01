# typed: strict
# frozen_string_literal: true

require "base64"

class Stafftools::Copilot::MetricsComponent < ApplicationComponent

  sig { returns(Copilot::Organization) }
  attr_reader :copilot_organization

  sig { params(copilot_organization: Copilot::Organization).void.checked(:always).on_failure(:raise) }
  def initialize(copilot_organization)
    @copilot_organization = copilot_organization
  end

  sig { returns(String) }
  def base_url
    "https://dataexplorer.azure.com/clusters/ghdwprod.eastus/databases/copilot"
  end

  sig { returns(String) }
  def raw_query
    <<~HEREDOC
    let query_org_name = "#{@copilot_organization.organization_object.display_login}";
    let timeframe = -28d;
    let query_org_id = database("snapshots_all").GetLatestSnapshotView(database("snapshots_all").github_mysql1_users)
      | where login == query_org_name and type == "Organization"
      | limit 1
      | project id;
    let cfb_users = database("snapshots_all").github_copilot_copilot_seats
      | where startofday(todatetime(snapshot_date)) >= startofday(now(timeframe)) and organization_id in(query_org_id)
      | project assigned_user_id, day = startofday(todatetime(snapshot_date))
      | join kind=inner hint.strategy=shuffle (
          database("snapshots_all").GetLatestSnapshotView(database("snapshots_all").github_mysql1_users)
          | where type == "User" and spammy == false
          | project analytics_tracking_id, dotcom_id = id
      ) on $left.assigned_user_id == $right.dotcom_id
      | project day, analytics_tracking_id
      | limit 250000;
    let Events = database("hydro").copilot_v0_copilot_event
      | where name in ("copilot/ghostText.shown","copilot/ghostText.accepted") and startofday(timestamp) >= startofday(now(timeframe)) and comp_type != "partial" //removing partial accepts
      | where isnotempty(header_request_id) and isnotempty(choice_index)
      | project day = startofday(todatetime(timestamp)), name, copilot_tracking_id, header_request_id, choice_index, language_id, num_lines;
    cfb_users
      | join kind=inner hint.strategy=shuffle (
              Events
          ) on $left.analytics_tracking_id == $right.copilot_tracking_id and $left.day == $right.day
      | project day, name, header_request_id,choice_index, language_id, num_lines
      | extend req_choice = strcat(tostring(header_request_id),'_', tostring(coalesce(choice_index,0)))
      | extend shown=iff(name=='copilot/ghostText.shown',1,0), acc=iff(name=='copilot/ghostText.accepted',1,0)
      | summarize hint.strategy = shuffle s=max(shown), a=max(acc), num_lines=sum(num_lines) by week=startofweek(day), language_id, req_choice//, language_id //useful for request acceptance rate
      | summarize hint.strategy = shuffle acceptances=countif(a==1), shown=countif(s==1), num_lines_accepted=sumif(num_lines, a==1) by week, language_id
      | project week, language=language_id, acceptances, shown, acceptance_percent=round(100.0 * acceptances / shown, 2), num_lines_accepted;
    HEREDOC
  end

  sig { returns(String) }
  def acceptances_by_language_query
    compressed = ActiveSupport::Gzip.compress(raw_query)
    base64 = Base64.encode64(compressed)
    URI.encode_www_form_component(base64)
  end
end
