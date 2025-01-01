# typed: strict
# frozen_string_literal: true

class Copilot::ActivityReportJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
  locked_by timeout: 10.minutes, key: DEFAULT_LOCK_PROC

  resolve_tenant_context do |args|
    if args[:entity_type].downcase == "organization"
      ::Organization.find_by(id: args[:entity_id])&.business
    else
      ::Business.find_by(id: args[:entity_id])
    end
  end

  # A magic number to estimate additional bytesize that might be introduced
  # due to line breaks when the base64 string wraps, every 76 chars.
  MAGIC_CRLF_VALUE = 2
  STORAGE_SIZE_THRESHOLD = T.let(15.megabytes, Integer)

  sig do
    params(
      entity_type: String,
      entity_id: Integer,
      actor_id: Integer
    ).void
  end
  def perform(entity_type:, entity_id:, actor_id:)
    @actor = T.let(::User.find_by(id: actor_id), T.nilable(::User))

    return handle_error("User not found", { "gh.user.id" => actor_id }) unless @actor

    @entity = T.let(find_entity(entity_type, entity_id), T.nilable(T.any(::Organization, ::Business)))
    return handle_error("Entity not found", {
      "gh.copilot.entity_type" => entity_type,
      "gh.copilot.entity_id" => entity_id
    }) unless @entity

    GitHub.logger.with_named_tags(
      "gh.copilot.entity_type" => entity_type,
      "gh.copilot.entity_id" => entity_id,
      "gh.user.id" => @actor.id
    ) do
      # Generate the CSV report
      result = generate_activity_csv(@entity)

      unless result.ok?
        handle_copilot_error(
          Copilot::Errors::ActivityReportGenerationError.new(result.error.message), {
          "gh.copilot.entity_type" => entity_type,
          "gh.copilot.entity_id" => entity_id
        })
        return
      end

      csv_data, filename = result.value!

      if csv_data
        send_activity_report(csv_data, filename)
      else
        GitHub.logger.info("No activity data found, sending no data email")
        CopilotGeneralMailer.activity_report_no_data(@actor, @entity).deliver_later
        GitHub.dogstats.increment("copilot.activity_report_job.no_data", tags: ["entity_type:#{entity_type}"])
      end
    end
  end

  private

  sig { params(entity_type: String, entity_id: Integer).returns(T.nilable(T.any(::Organization, ::Business))) }
  def find_entity(entity_type, entity_id)
    case entity_type.downcase
    when "organization"
      ::Organization.find_by(id: entity_id)
    when "business"
      ::Business.find_by(id: entity_id)
    else
      nil
    end
  end

  sig { params(entity: T.any(::Organization, ::Business)).returns(GitHub::Result) }
  def generate_activity_csv(entity)
    GitHub.logger.info("Generating activity CSV")
    copilot_entity = entity.is_a?(::Organization) ? Copilot::Organization.new(entity) : Copilot::Business.new(entity)
    GitHub::Result.new do
      [copilot_entity.to_activity_csv, copilot_entity.get_activity_report_filename]
    end
  end

  # When ActiveMailer generates the attachment for the CSV, it encodes that data as base64.
  # The encoding adds ~33% to the total size of the attachment.
  sig { params(csv_data: String).returns(T::Boolean) }
  def data_needs_storage?(csv_data)
    data_size = csv_data.bytesize
    base64_encoded_size = (4 * (data_size + MAGIC_CRLF_VALUE) / 3)
    estimated_email_encoded_size = (base64_encoded_size * 1.02).to_i
    storage_threshold = FeatureFlag.vexi.enabled?(:copilot_activity_job_min_storage_size, @actor, default: false) ? 1.megabyte : STORAGE_SIZE_THRESHOLD

    needs_storage = estimated_email_encoded_size > storage_threshold

    GitHub.logger.info("Activity report size evaluation",
      "gh.copilot.activity_csv.size_in_mb" => (estimated_email_encoded_size.to_f / 1.megabyte).round(2),
      "gh.copilot.activity_csv.storage_needed" => needs_storage,
    )

    needs_storage
  end

  sig { params(csv_data: String, filename: String).void }
  def send_activity_report(csv_data, filename)
    entity = T.must(@entity)
    entity_type = entity.class.name&.downcase&.to_sym

    return handle_copilot_error(
      Copilot::Errors::ActivityReportGenerationError.new("Unknown entity supplied"), {
        "gh.copilot.entity_type" => entity_type,
        "gh.copilot.entity_id" => entity.id
      }
    ) unless entity_type

    if data_needs_storage?(csv_data)
      export = Copilot::ActivityReportStorage.new(
        entity_id: entity.id,
        entity_type: entity_type,
      )
      result = export.store(filename: filename, content: csv_data)

      return handle_copilot_error(
        result.error, {
          "gh.copilot.entity_type" => entity_type,
          "gh.copilot.entity_id" => entity.id
        }
      ) unless result.ok?

      download_url = export.download_url(result.value!.name, expires_in: 24.hours, content_type: "text/csv")
      CopilotGeneralMailer.activity_report_download(T.must(@actor), entity, download_url).deliver_later
      GitHub.dogstats.increment("copilot.activity_report_job.use_blob_storage", tags: ["entity_type:#{entity_type}"])
    else
      GitHub.logger.info("Activity report generated successfully, sending email")
      CopilotGeneralMailer.activity_report(T.must(@actor), entity, csv_data, filename).deliver_later
      GitHub.dogstats.increment("copilot.activity_report_job.use_attachment", tags: ["entity_type:#{entity_type}"])
    end

    GitHub.dogstats.increment("copilot.activity_report_job.success", tags: ["entity_type:#{entity_type}"])
  end
end
