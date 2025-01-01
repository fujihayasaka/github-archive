# typed: true
# frozen_string_literal: true

class Repos::CodeScanning::ToolStatus::RulesController < Repos::CodeScanning::ToolStatus::AbstractController
  before_action :login_required,
    :check_code_scanning_read,
    :default_branch_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  track_latency_slo "p99-ui-request", 3000, only: [:show]
  track_latency_slo "p50-ui-request", 750, only: [:show]

  def show
    response = GitHub::Turboscan.get_tool_status_rules(
      repository_id: current_repository.id,
      ref: current_repository.default_branch_ref.qualified_name,
      tool: params[:tool_name],
      analysis_ids: params.fetch(:ids, []).map(&:to_i),
    )

    return render_404 if response.nil?
    raise StandardError.new(response.error&.msg) if response.error.present?

    data = CSV.generate do |csv|
      csv << ["Configuration", "Rule Source", "Sarif Identifier", "Alerts"]
      response.data.categories.each do |category, category_rules|
        category_rules.origins.each do |rule_origin|
          rule_source = if rule_origin.origin.version.blank?
            rule_origin.origin.name
          else
            "#{ rule_origin.origin.name } (#{rule_origin.origin.version})"
          end
          rule_origin.rules.each do |rule|
            csv << [category, rule_source, rule.sarif_identifier, rule.results]
          end
        end
      end
    end

    send_data data, filename: "code-scanning-rules-used.csv"
  end
end
