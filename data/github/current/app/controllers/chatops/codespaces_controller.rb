# typed: true
# frozen_string_literal: true

require "chatops-controller"
require "terminal-table"

class Chatops::CodespacesController < ApplicationController
  include ::Chatops::Controller
  include ::GitHubChatopsExtensions::Checks::Includable::Fido
  include ::GitHubChatopsExtensions::Checks::Includable::Entitlements
  include ::GitHubChatopsExtensions::Checks::Includable::Room

  # Opt-out of all conditional access and secondary authn checks
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:list]

  CONTROLLED_ACTIONS = [:failover, :failover_restore].freeze
  ALLOWED_ROOMS = ["#codespaces-ops"].freeze
  ALLOWED_TEAMS = ["pizza_teams/codespaces"].freeze

  SENTRY_URL = "https://github.sentry.io/issues/?query=is%3Aunresolved+code.namespace%3A%22Chatops%3A%3ACodespacesController%22"
  KUSTO_ENDPOINT = "https://vsonline.kusto.windows.net/v2/rest/query"
  SUBSTRATE_ENDPOINT = "https://fe-26.qas.bing.net/sdf/completions"
  SUBSTRATE_PROMPT = "app/controllers/chatops/assets/codespaces_prompt.txt"
  SUBSTRATE_PROGRESS_DESCRIPTIONS = "app/controllers/chatops/assets/codespaces_progress_description.csv"
  KUSTO_QUERY = "app/controllers/chatops/assets/codespaces_kusto_query.kql"
  KUSTO_SCOPE = "https://help.kusto.windows.net/.default"

  before_action :require_fido_2fa_when_confirming, only: CONTROLLED_ACTIONS
  before_action -> { T.bind(self, Chatops::CodespacesController); require_in_room(ALLOWED_ROOMS) }, only: CONTROLLED_ACTIONS
  before_action -> { T.bind(self, Chatops::CodespacesController); require_ldap_entitlement(ALLOWED_TEAMS) }, only: CONTROLLED_ACTIONS

  NAME_REGEX = %r{
    \A
    (?:https://)?         # Optional beginning of Codespace URL
    (?<name>[a-z0-9\-]+)  # The codespace name - standalone or as a subdomain
    (?:\.github\.dev/?)?  # Optional end of Codespace URL
    \z
  }ix

  CODESPACE_VSCS_DATABASE_NAMES = {
    production: "CodespacesProd",
    ppe: "CodespacesPpe",
    development: "CodespacesDev"
  }

  chatops_namespace :codespaces
  chatops_help "Commands for working with Codespaces"
  chatops_error_response "More information is available [in Sentry](#{SENTRY_URL})"

  chatop :diagnose,
         /diagnose(?:\s+(?<name_or_id>\S+))/,
         "diagnose <codespace name or id> - Diagnose failed connection in the codespace" do
    name_or_id = jsonrpc_params.require(:name_or_id)
    unless match = NAME_REGEX.match(name_or_id)
      chatop_send("Invalid codespace name or id: #{name_or_id}")
      return
    end

    # find by name first (original behavior)
    codespace = Codespace.include_deleted.find_by(name: match[:name])

    # see if we were passed a guid
    codespace ||= Codespace.include_deleted.find_by(guid: match[:name]) if codespace.nil?

    # look up the billing entry directly in case we were passed a name/guid for a deleted codespace
    billing_entry = codespace&.billing_entry || Codespaces::BillingEntry.latest(match[:name])

    unless codespace || billing_entry
      chatop_send("Codespace **#{match[:name]}** not found by name, guid or ID")
      return
    end

    codespace_guid = codespace&.guid || billing_entry&.codespace_guid

    client_id = GitHub.environment.fetch("CODESPACES_CHAT_APP_ID")
    tenant_id = GitHub.sdn_authentication_tenant_id
    client_secret = GitHub.environment.fetch("CODESPACES_CHAT_SECRET_KEY")

    begin
      # Get Substrate API token
      substrate_token = get_access_token(
        tenant_id:,
        client_id:,
        client_secret:,
        scope: "api://#{client_id}/.default"
      )

      # Get Kusto token
      kusto_token = get_access_token(
        tenant_id:,
        client_id:,
        client_secret:,
        scope: KUSTO_SCOPE
      )

      # Get prompt to send to Substrate LLM
      prompt = File.read(File.join(Rails.root, SUBSTRATE_PROMPT)).to_s
      progress_description_csv = CSV.read(File.join(Rails.root, SUBSTRATE_PROGRESS_DESCRIPTIONS)).to_s

      # Get the Kusto data
      headers = {
        "Content-Type": "application/json",
        "Authorization": "Bearer #{kusto_token}"
      }

      # Get the Kusto query
      query = File.read(File.join(Rails.root, KUSTO_QUERY)).to_s.sub("$CODESPACE_GUID$", codespace_guid)

      body = {
        "db": "CodespacesProd",
        "csl": query
      }.to_json

      kusto_data = perform_post_request(url: KUSTO_ENDPOINT, headers:, body:)
      result_table = kusto_data.find { |t| t["TableName"] == "PrimaryResult" }

      if result_table
        kusto_csv = result_table["Rows"].map { |row| row.join(",") }.join("\n")
      else
        chatop_send "No query results found."
      end

      # Replace the prompt with all the data
      prompt = prompt.sub("$KUSTO_CSV$", kusto_csv)
      prompt = prompt.sub("$DESCRIPTION_CSV$", progress_description_csv)

      # Send request to Substrate LLM
      headers = {
        "Content-Type": "application/json",
        "Authorization": "Bearer #{substrate_token}",
        "X-ModelType": "dev-moonshot",
        "X-CV": SecureRandom.uuid
      }
      body = {
        "prompt": prompt,
        "max_tokens": 1024,
        "temperature": 1,
        "top_p": 1,
        "n": 1,
        "stream": false
      }.to_json

      substrate_data = perform_post_request(url: SUBSTRATE_ENDPOINT, headers:, body:)

      # Return all choices
      result = substrate_data["choices"].map { |choice| choice["text"] }.join("\n")
      chatop_send result
    rescue => e
      chatop_send e
    end
  end

  chatop :info,
         /info(?:\s+(?<name_or_url>\S+))/,
         "info <codespace name or URL> - Show some information about a codespace" do
    name_or_url = jsonrpc_params.require(:name_or_url)
    unless match = NAME_REGEX.match(name_or_url)
      chatop_send("Invalid codespace name or URL: #{name_or_url}")
      return
    end

    # find by name first (original behavior)
    codespace = Codespace.include_deleted.find_by(name: match[:name])

    # see if we were passed a guid
    codespace = Codespace.include_deleted.find_by(guid: match[:name]) if codespace.nil?

    # see if we were passed a dotcom database ID
    if codespace.nil? && match[:name]&.match(/\A\d+\Z/)
      codespace = Codespace.include_deleted.find_by(id: match[:name].to_i)
    end

    # look up the billing entry directly in case we were passed a name/guid for a deleted codespace
    billing_entry = codespace&.billing_entry || Codespaces::BillingEntry.latest(match[:name])

    unless codespace || billing_entry
      chatop_send("Codespace **#{match[:name]}** not found by name, guid or ID")
      return
    end

    codespace_info = {}

    # start with a billing_entry if found
    if billing_entry
      codespace_info = codespace_info.merge(
        "GUID" => billing_entry.codespace_guid,
        "Billable Owner ID" => billing_entry.billable_owner_id,
        "Owner ID" => billing_entry.codespace_owner_id,
        "Repository ID" => billing_entry.repository_id,
        "Created At" => billing_entry.codespace_created_at,
        "Deprovisioned At" => billing_entry.codespace_deprovisioned_at,
        "Deleted At" => billing_entry.codespace_deleted_at
      )
    else
      codespace_info = codespace_info.merge(
        "Billing Entry" => "Not Found"
      )
    end

    # let codespace details overrule (though they should be the same)
    if codespace
      codespace_info = codespace_info.merge(
        "Database ID" => codespace.id,
        "GUID" => codespace.guid,
        "Name" => codespace.name,
        "Location" => codespace.location,
        "Explorer dashboard" => "[link](#{"https://dataexplorer.azure.com/dashboards/85e78a01-429d-4f21-9a8e-017691a63c83?p-_codespace_id=v-#{codespace.guid}&p-_database=v-#{codespaces_database_param(codespace)}"})",
        "Deleted At" => codespace.deleted_at,
        "Deleted Reason" => codespace.deletion_reason&.humanize,
        "Deleted" => codespace.deleted_at.present? ? "yes" : "no"
      )

      if codespace.copilot_workspace?
        codespace_info = codespace_info.merge("Copilot Workspace ID" => codespace.copilot_workspace_id)
      end

      if codespace.owner.present?
        codespace_info = codespace_info.merge(
          "GitHub Stafftools" => "[link](https://admin.github.com/stafftools/users/#{codespace.owner&.login}/codespaces/#{codespace.name})"
        )
      else
        codespace_info = codespace_info.merge(
          "GitHub Stafftools" => "unavailable — codespace owner not found"
        )
      end

      # this is generally a lot of info, so make sure it's hidden by default in the slack message
      codespace_info = codespace_info.merge("Environment Data" => "```#{JSON.pretty_generate(codespace.environment_data.as_json)}```")
    else
      codespace_info = codespace_info.merge("Deleted" => "yes")
    end

    formatted_lines = codespace_info.map do |key, value|
      "*#{key}:* #{value}"
    end

    chatop_send formatted_lines.join("\n")
  end

  chatop :failover, /failover redirect(?:\s+(?<region>\S+)) in (?:\s*(?<target>\S+))/, "failover redirect <region> in <production | prod | ppe | development | dev> [--confirm] [--only <creates|resumes>] [--percent <percentage>] - Failover by redirecting requests for the region in the target" do
    return unless vscs_target = require_valid_target!

    actor = params.fetch(:user)
    user = User.find_by_login(actor)
    return unless stamp = require_valid_stamp!(vscs_target)

    available_backups = stamp.available_backups(user:)
    backups_string = available_backups.map { |s| "`#{s.region.id}`" }.to_sentence
    if available_backups.present?
      confirmed = jsonrpc_params[:confirm].present?
      percent = jsonrpc_params[:percent].present? ? jsonrpc_params[:percent].to_i : nil
      if confirmed
        only = jsonrpc_params[:only]
        only_message = only ? "for #{only} " : ""

        ::Codespaces::ToggleFailoverJob.perform_later(region: stamp.region.id, vscs_target: stamp.vscs_target, redirect: true, only:, codespaces_repository: nil, actor:, percent:)

        chatop_send <<~MSG
          :hourglass_flowing_sand: A job has been queued to enable redirect #{only_message}from `#{stamp.region.id}` to #{backups_string} in `#{vscs_target}` for all stamps:
              - It may take a minute for the job to complete
              - Check the [region selection dashboard](https://app.datadoghq.com/dashboard/ey5-wis-f2k/codespaces-region-selection) to confirm traffic was redirected
              - If traffic is not redirected, check [Sentry](https://github.sentry.io/issues/?environment=canary&environment=production&project=1885898&query=is%3Aunresolved+cause_catalog_service%3Agithub%2Fcodespaces+%21is%3Alinked+%21is%3Aignored&referrer=issue-list&statsPeriod=1h) for errors
              - Restore #{stamp.region.id} by running `.codespaces failover restore #{stamp.region.id} in #{vscs_target}`

          Good luck!
        MSG
      else
        pool_sizings_string = available_backups.map { |s| "[#{s.region.id}](https://dataexplorer.azure.com/dashboards/4ae25b53-4457-4652-901b-740121636c67?p-_databaseName=v-CodespacesProd&p-_location=v-#{s.region.id.downcase})" }.to_sentence
        chatop_send <<~MSG
          :warning: This will enable redirects from `#{stamp.region.id}` to #{backups_string} in `#{vscs_target}` for all stamps.

          Consider reviewing the backup regions' pool sizing for #{pool_sizings_string} to ensure we can serve more traffic.

          To confirm, add `--confirm` to the command.
        MSG
      end
    else
      chatop_send <<~MSG
        :error: '#{stamp.region.id}' in target '#{vscs_target}' currently has NO available backups.
      MSG
    end
  end

  chatop :failover_restore, /failover restore(?:\s+(?<region>\S+)) in (?:\s*(?<target>\S+))/, "failover restore <region> in <production | prod | ppe | development | dev> [--confirm] [--only <creates|resumes>] - Restore traffic for the region in the target" do
    return unless vscs_target = require_valid_target!

    actor = params.fetch(:user)
    return unless stamp = require_valid_stamp!(vscs_target)

    confirmed = jsonrpc_params[:confirm].present?
    if confirmed
      only = jsonrpc_params[:only]
      only_message = only ? "for #{only} " : ""

      ::Codespaces::ToggleFailoverJob.perform_later(region: stamp.region.id, vscs_target: stamp.vscs_target, redirect: false, only:, codespaces_repository: nil, actor:)

      chatop_send <<~MSG
        :hourglass_flowing_sand: A job has been queued to restore traffic #{only_message}to `#{stamp.region.id}` in `#{vscs_target}` for all stamps:
            - It may take a minute for the job to complete
            - Check the [region selection dashboard](https://app.datadoghq.com/dashboard/ey5-wis-f2k/codespaces-region-selection) to confirm traffic was restored
            - If traffic is not redirected, check [Sentry](https://github.sentry.io/issues/?environment=canary&environment=production&project=1885898&query=is%3Aunresolved+cause_catalog_service%3Agithub%2Fcodespaces+%21is%3Alinked+%21is%3Aignored&referrer=issue-list&statsPeriod=1h) for errors

        Good luck!
      MSG
    else
      chatop_send <<~MSG
        :warning: This will restore traffic to `#{stamp.region.id}` in `#{vscs_target}` for all stamps.

        To confirm, add `--confirm` to the command.
      MSG
    end
  end

  chatop :failover_list, /failover list in (?:\s*(?<target>\S+))/, "failover list in <production | prod | ppe | development | dev> - List failover status for all regions in the target" do
    return unless vscs_target = require_valid_target!

    actor = params.fetch(:user)

    table = Terminal::Table.new(title: "Failover status for #{vscs_target}", headings: ["Region", "Allow creates", "Allow resumes"])
    ::Codespaces::VscsServiceStamp.where(vscs_target:).each do |stamp|
      create_availability = format_pct_available(stamp.percent_available_for_creates)
      resume_availability = format_pct_available(stamp.percent_available_for_resumes)

      table << [stamp.region.id, create_availability, resume_availability]
    end
    chatop_send <<~MSG
      ```
      #{table}
      ```
    MSG
  end

  private

  def format_pct_available(pct)
    case pct
    when 100 then "✅ 100%"
    when 0 then "❌ 0%"
    else "🟡 #{pct}%"
    end
  end

  def require_valid_target!
    target = jsonrpc_params.require(:target)
    vscs_target = normalize_target(target)
    vscs_target
    if ::Codespaces::Vscs.targets.include?(vscs_target)
      vscs_target
    else
      chatop_send "Error: unknown vscs_target `#{target}`"
      nil
    end
  end

  def require_valid_region_name!(vscs_target)
    region = jsonrpc_params.require(:region)
    region = region_shortcode_to_region_name(region)
    normalized_region = ::Codespaces::Locations::Region.where(vscs_target:).find(region)
    if normalized_region
      normalized_region.id
    else
      chatop_send "Error: unknown region `#{region}`"
      nil
    end
  end

  def require_valid_stamp!(vscs_target)
    region = jsonrpc_params.require(:region)
    region = region_shortcode_to_region_name(region)
    stamp = ::Codespaces::VscsServiceStamp.find(region: region, vscs_target:)
    if stamp
      stamp
    else
      chatop_send "Error: unknown region `#{region}`"
      nil
    end
  end

  def normalize_target(vscs_target)
    normalized_target = if vscs_target == "prod"
      "production"
    elsif vscs_target == "dev"
      "development"
    else
      vscs_target
    end

    normalized_target.to_sym
  end

  def region_shortcode_to_region_name(shortcode)
    case shortcode
    when "asse"
      "SouthEastAsia"
    when "auc"
      "AustraliaCentral"
    when "aue"
      "AustraliaEast"
    when "inc"
      "CentralIndia"
    when "euw"
      "WestEurope"
    when "uks"
      "UkSouth"
    when "use"
      "EastUs"
    when "use2"
      "EastUs2"
    when "usw2"
      "WestUs2"
    when "usw3"
      "WestUs3"
    when "cac"
      "CanadaCentral"
    else
      shortcode
    end
  end

  def verify_authenticity_token?
    false # robots do this
  end

  def require_fido_2fa_when_confirming
    return unless jsonrpc_params[:confirm].present?

    require_fido_2fa
  end

  def codespaces_database_param(codespace)
    CODESPACE_VSCS_DATABASE_NAMES[codespace.plan.vscs_target]
  end

  def get_access_token(tenant_id:, client_id:, client_secret:, scope:)
    body = [
      "client_id=#{client_id}",
      "client_secret=#{client_secret}",
      "grant_type=client_credentials",
      "scope=#{scope}"
    ].join("&")
    resp = faraday.post do |req|
      req.url "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token"
      req.headers["Content-Type"] = "application/x-www-form-urlencoded"
      req.body = body
    end
    if resp.status != 200
      err_desc = JSON.parse(resp.body).dig("error_description")
      if err_desc.include?("Unauthorized") || err_desc.include?("Invalid client secret")
        raise "Invalid client credentials"
      else
        raise "Unknown error: #{resp.status}"
      end
    end

    GitHub::JSON.parse(resp.body)["access_token"]
  end

  def perform_post_request(url:, headers:, body:)
    resp = faraday.post do |req|
      req.url url
      req.headers = headers
      req.body = body
    end
    if resp.status != 200
      raise "Unknown error: #{resp.status}"
    end

    GitHub::JSON.parse(resp.body)
  end

  def faraday
    GitHub::FaradayClient::External.new do |c|
      c.adapter Faraday.default_adapter
    end
  end
end
