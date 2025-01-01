# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class WindbeamExportJob < ApplicationJob
  class MaxDurationReachedError < StandardError
  end

  queue_as :windbeam_export

  POLLING_INTERVAL = 1.hour
  MAX_RETRIES = 5
  MAX_EXPORT_DURATION = 7.days

  RETRYABLE_ERRORS = [
    WindbeamApi::Errors::CommunicationError,
    Faraday::TimeoutError,
    Faraday::ConnectionFailed,
    ActiveRecord::ConnectionNotEstablished,
    ActiveRecord::ConnectionFailed,
  ].freeze

  RETRYABLE_ERRORS.each do |error_class|
    retry_on error_class, wait: :polynomially_longer, attempts: MAX_RETRIES do |job, error|
      job.fail_export_and_raise(error)
    end
  end

  retry_on_dirty_exit

  def perform(user_id, export_id = nil)
    @user = User.find_by(id: user_id)
    return false unless @user

    with_write do
      @export = export_id.nil? ? create_export : WindbeamExport.find_by(id: export_id)

      # sanity check
      if @export.nil?
        GitHub.dogstats.increment "windbeam.export.job", tags: ["error:export_not_found"]
        error_message = "Windbeam export creation failed/record not found"
        Failbot.report(StandardError.new(error_message))
        raise StandardError.new(error_message)
      end

      if Time.current - @export.created_at > MAX_EXPORT_DURATION && !@export.completed?
        GitHub.dogstats.increment "windbeam.export.job", tags: ["error:timeout"]
        GitHub.logger.warn "WindbeamExportJob timed out for user #{user_id}, export #{@export.id}"
        fail_export_and_raise(MaxDurationReachedError.new("Export not completed within #{MAX_EXPORT_DURATION.inspect}"))
        return
      end

      case @export.state.to_sym
      when :pending
        start_export
      when :in_progress
        check_export_status
      when :completed
        process_completed_export
      when :failed
        fail_export_and_raise(StandardError.new("Export failed"))
      end
    end
  rescue ActiveRecord::RecordNotFound => e
    Failbot.report(e)
    GitHub.logger.error "User or export not found: #{e.message}"
  end

  def fail_export_and_raise(error)
    @export.fail_export
    GitHub.logger.error "WindbeamExportJob failed for user #{@user&.id}: #{error.message}"
    raise error
  end

  private

  def create_export
    begin
      req_id = Dsr.export_user(@user)
      # see https://apidock.com/rails/v4.0.2/ActiveRecord/Relation/create
      export = WindbeamExport.where(user_id: @user.id, request_id: req_id)
      export.create
    rescue WindbeamApi::Errors::CommunicationError => e
      GitHub.dogstats.increment "windbeam.export.job", tags: ["error:create_export"]
      Failbot.report(e)
      nil
    end
  end

  def start_export
    @export.start_export
    reschedule_job
  end

  def check_export_status
    azure_url = fetch_download_url

    case azure_url
    when nil
      reschedule_job
    when :nothing_to_export
      GitHub.logger.info "WindbeamExportJob: Nothing to export for user #{@user.id}, export #{@export.id}"
      GitHub.dogstats.increment "windbeam.export.job", tags: ["status:nothing_to_export"]
      @export.complete_export # Mark the export as completed without further actions
    else
      process_completed_export(azure_url)
      @export.complete_export
    end
  end

  def process_completed_export(azure_url = nil)
    if azure_url.nil?
      azure_url = fetch_download_url
    end
    @export.set_azure_url(azure_url)
    GitHub.logger.info "Successfully retrieved SAS URL for user #{@user.id}, export #{@export.id}: #{azure_url}"
    final_url = File.join(GitHub.url, @export.url_with_token)
    AccountMailer.download_windbeam(@user, final_url).deliver_later
    GitHub.dogstats.increment "windbeam.export.job", tags: ["status:azure_url_retrieved"]
  end

  def fetch_download_url
    begin
      Dsr.windbeam_client.get_download_url(@export.request_id, "")
    rescue WindbeamApi::Errors::CommunicationError => e
      if e.message.include?("Nothing to export")
        :nothing_to_export
      elsif e.message.include?("No exports found")
        nil # Retryable case, no export found yet
      else
        nil # Retryable case for other communication errors
      end
    end
  end

  def reschedule_job
    self.class.set(wait: WindbeamExportJob::POLLING_INTERVAL).perform_later(@user.id, @export.id)
  end
end
