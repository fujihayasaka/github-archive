# frozen_string_literal: true

# rubocop:disable Metrics/ModuleLength
module ChatopWorkflowPausing
  extend ActiveSupport::Concern

  class MissingQueueError < StandardError; end

  PLAYBOOK_URL_EXCESSIVE_BACKLOG = "https://github.com/github/ops/blob/master/docs/playbooks/dependabot/excessive-pr-backlog.md"
  FIDO_PROTECTED_ACTIONS = %i(pause_all resume_all).freeze

  included do # rubocop:disable Metrics/BlockLength
    before_action :require_fido_2fa, only: FIDO_PROTECTED_ACTIONS

    chatop :pause_all,
           /pause[-_]all/,
           "pause-all - Pause all Aqueduct queues and Hydro consumers" do
      aqueduct_table = pause_all_aqueduct_queues
      hydro_table = pause_all_hydro_consumers

      # Set paused status and timestamp
      Dependabot.redis.set("dependabot_paused_status", "true")
      Dependabot.redis.set("dependabot_pause_timestamp", Time.current.to_i)
      # Trigger NotifyDependabotStatusJob to start notifications
      NotifyDependabotStatusJob.perform_later

      # Explicitly return the success message to avoid returning the job object above
      return display_pause_all_messages(aqueduct_table, hydro_table)
    end

    chatop :resume_all,
           /resume[-_]all/,
           "resume-all - Resumes all Aqueduct queues and Hydro consumers" do
      aqueduct_table = resume_all_aqueduct_queues
      hydro_table = resume_all_hydro_consumers

      # Clear paused status and timestamp in Redis
      Dependabot.redis.set("dependabot_paused_status", "false")
      Dependabot.redis.del("dependabot_pause_timestamp")

      # Add status command to remove yellow/red status
      remove_status_command = ".status-internal clear dependabot Dependabot is back to normal service."

      # Explicitly return the success message
      return jsonrpc_success(
        [
          "*Resumed Aqueduct Queues*:",
          "```", aqueduct_table.to_s, "```",
          "*Resumed Hydro Consumers*:",
          "```", hydro_table.to_s, "```",
          "",
          ":information_source: *Next Steps*:",
          "1. Confirm that Dependabot services are fully operational.",
          "2. Clear the status by running the following command:",
          "   ```", remove_status_command, "```",
        ].join("\n")
      )
    end

    private

    def display_pause_all_messages(aqueduct_table, hydro_table)
      jsonrpc_success(
        [
          "*Paused Aqueduct queues*:",
          "```", aqueduct_table.to_s, "```",
          "*Paused Hydro consumers*:",
          "```", hydro_table.to_s, "```",
          "",
          ":information_source: *Next Steps*:",
          "1. Update Dependabot status using `.status-internal` or through status.githubapp.com:",
          "   - For degraded service: `.status-internal yellow dependabot Degraded service due to <reason>`",
          "   - For unavailable service: `.status-internal red dependabot Service unavailable`",
          "2. Notify `#incident-command` of the status update and ongoing actions.",
          "3. Open an [incident tracking issue](https://github.com/",
          "   github/dependabot-updates/issues/new?template=6-incident.md) ",
          "   to log the timeline and actions taken.",
        ].join("\n")
      )
    end

    def auth_header
      token_expiration = Time.now.utc.to_i + 5.minutes
      token = [token_expiration, Prius.get(:aqueduct_api_key_version)].join(":")
      signature = OpenSSL::HMAC.hexdigest("sha256", Prius.get(:aqueduct_api_key), token)
      "HMAC-256 #{token}:#{signature}"
    end

    def aqueduct_queues
      JSON.parse(Excon.post(
        "#{Prius.get(:aqueduct_url)}/aqueduct.api.v1.JobQueueService/ListQueues",
        body: '{"app": "dependabot-api"}',
        headers: {
          "Content-Type" => "application/json",
          "Authorization" => auth_header,
        }
      ).body).fetch("queues", [])
    end

    def pause_all_aqueduct_queues
      results = aqueduct_queues.map do |queue|
        body = { app: "dependabot-api", queue: queue["name"] }
        Excon.post("#{Prius.get(:aqueduct_url)}/aqueduct.api.v1.JobQueueService/AddPausingRule",
                   body: body.to_json,
                   headers: {
                     "Content-Type" => "application/json",
                     "Authorization" => auth_header,
                   })
        [queue["name"], "paused"]
      end

      Terminal::Table.new do |t|
        t.headings = %w(Queue Status)
        t.rows = results
      end
    end

    def pause_all_hydro_consumers
      ProcessorManager.pause("all")

      Terminal::Table.new do |t|
        t.headings = %w(Processor Status)
        t.rows = ProcessorManager.current_status
      end
    end

    def resume_all_aqueduct_queues
      results = aqueduct_queues.map do |queue|
        body = { app: "dependabot-api", queue: queue["name"] }
        Excon.post("#{Prius.get(:aqueduct_url)}/aqueduct.api.v1.JobQueueService/RemovePausingRule",
                   body: body.to_json,
                   headers: {
                     "Content-Type" => "application/json",
                     "Authorization" => auth_header,
                   })
        [queue["name"], "active"]
      end

      Terminal::Table.new do |t|
        t.headings = %w(Queue Status)
        t.rows = results
      end
    end

    def resume_all_hydro_consumers
      ProcessorManager.resume("all")

      Terminal::Table.new do |t|
        t.headings = %w(Processor Status)
        t.rows = ProcessorManager.current_status
      end
    end
  end
end
# rubocop:enable Metrics/ModuleLength
