# typed: true
# frozen_string_literal: true

module SourceImport
  class Notifier
    class UnsupportedMessageType < StandardError; end

    COMPLETED_STATUS_MAPPINGS = {
      "succeeded"         => "success",
      "failed"            => "failure",
      "failed_validation" => "failure",
    }.freeze

    STATUS_MESSAGE_TYPE_MAPPINGS = {
      "succeeded"         => "import_success",
      "failed"            => "import_failure",
      "failed_validation" => "import_failure",
    }.freeze

    attr_reader :repository, :user, :status, :failure_reason, :error_details

    def initialize(
      repository:,
      user:,
      status:,
      failure_reason: nil,
      error_details: [],
      notify_by_webhook: true,
      notify_by_mail: true
    )
      @repository = repository
      @user = user
      @status = status
      @failure_reason = failure_reason
      @error_details = error_details
      @notify_by_webhook = notify_by_webhook
      @notify_by_mail = notify_by_mail
    end

    def message_type
      STATUS_MESSAGE_TYPE_MAPPINGS[status].to_s
    end

    def completed_status
      COMPLETED_STATUS_MAPPINGS[status]
    end

    def notify_if_complete
      return false unless completed_status

      notify
      true
    end

    private

    def notify_by_webhook?
      @notify_by_webhook
    end

    def notify_by_mail?
      @notify_by_mail
    end

    def validate_message_type
      return if completed_status

      raise(
        UnsupportedMessageType,
        "Unsupported \"message_type\" value from git-src-migrator: #{message_type}",
      )
    end

    def notify
      send_mail if notify_by_mail?
      enqueue_hook if notify_by_webhook?
    end

    def send_mail
      validate_message_type

      notifier_args = {
        repository:     repository,
        user:           user,
        status:         status,
        failure_reason: failure_reason,
        error_details:  error_details.to_a
      }

      case message_type
      when "import_success"
        SourceImportMailer.import_success(**notifier_args).deliver_later
      when "import_failure"
        SourceImportMailer.import_failure(**notifier_args).deliver_later
      end
    end

    def enqueue_hook
      validate_message_type

      GitHub.instrument(
        "repository_import.import",
        status:   completed_status,
        repo_id:  repository.id,
        actor_id: user.id,
      )
    end
  end
end
