# typed: true
# frozen_string_literal: true

# A tool to be used from the rails console.
# Manually requeue HydroMessageJobs from a csv of github.Repositories.V1.Pushed payloads
module Pushes
  class PushesHydroRequeuer

    attr_reader :event_count
    attr_reader :csv_data
    attr_reader :failed

    def initialize(csv_path)
      @csv_data = parse_csv(csv_path)
      @event_count = @csv_data.length
      @failed = []
    end

    def run(queue:, write: false, limit: nil, skip: nil, source_data: @csv_data)
      @failed = [] if write
      source_data.each_with_index do |row, idx|
        next if skip && idx < skip
        break if limit && idx >= limit

        puts "Processing row #{idx + 1} of #{source_data.count}"

        headers = row["headers"]
        encoded = GitHub.sync_hydro_publisher.encode(row.except("headers"), schema: "github.repositories.v1.Pushed", encoder: GitHub.hydro_encoder, timestamp: Time.now.to_f)

        if write
          response = GitHub.aqueduct_primary.send_job(queue: queue, payload: encoded, headers: headers)
          puts "#{response}"
        else
          puts "Would have sent job with message: #{row} and headers: #{headers} to queue: #{queue}"
        end
      rescue StandardError => e # rubocop:todo Lint/RescueException
        puts "Failed row #{idx + 1} with error: #{e.message}"
        @failed << row if write
      end

      puts "Done."
      puts "#{@failed.count} failed, use #retry_failed to rerun them." if @failed.any?
      nil
    end

    def retry_failed(queue:)
      run(queue:, write: true, source_data: @failed)
    end

    def save_failed(path:)
      if failed.empty?
        puts "None failed."
        return
      end

      CSV.open(path, "wb") do |csv|
        csv << failed.first.keys
        failed.each do |row|
          serialized_vals = row.map do |k, v|
            case k
            when "headers", "push_options", "excluded_pull_ids", "enabled_flags", "request_context"
              v.to_json
            when "ref_updates"
              v.map { |u| { "ref" => Base64.encode64(u["ref"]), "before" => u["before"], "after" => u["after"] } }.to_json
            else
              v
            end
          end

          csv << serialized_vals
        end
      end

      puts "Wrote #{failed.count} rows to #{path}"
    end

    private

    def parse_csv(csv_path)
      converter = lambda do |value, field_info|
        case field_info.header
        when "repository_id", "oauth_access_id", "user_programmatic_access_id", "installation_id", "total_ref_count", "ref_batch_number", "pusher_id"
          value.to_i
        when "headers", "push_options", "excluded_pull_ids", "enabled_flags"
          JSON.parse(value.empty? ? "{}" : value)
        when "request_context"
          # for some reason this is returned in Kusto as a string when it should be an int
          val = JSON.parse(value.empty? ? "{}" : value)
          val["user_session_id"] = val["user_session_id"].to_i
          val["v4_int"] = 0 if val["v4_int"] && val["v4_int"].to_i < 0 # ensure v4_int is not negative
          val
        when "pushed_at"
          Time.parse(value.empty? ? "{}" : value)
        when "ref_updates"
          JSON.parse(value.empty? ? "{}" : value).each { |u| u["ref"] = Base64.decode64(u["ref"]) }
        else
          value
        end
      end

      csv_data = []
      CSV.foreach(csv_path, headers: true, quote_char: '"', encoding: "bom|utf-8", converters: converter)&.with_index do |row, _idx|
        csv_data << row.to_h
      end

      csv_data
    end
  end
end
