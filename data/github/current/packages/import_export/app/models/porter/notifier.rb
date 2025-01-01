# typed: true
# frozen_string_literal: true

module Porter
  class Notifier
    class UnsupportedMessageType < StandardError; end

    COMPLETED_STATUS_MAPPINGS = {
      "import_success"   => "success",
      "import_failure"   => "failure",
      "import_cancelled" => "cancelled",
    }.freeze

    attr_reader :porter_data, :repository, :user

    def initialize(
      porter_data:,
      repository:,
      user:,
      notify_by_webhook: true,
      notify_by_mail: true
    )
      @porter_data = porter_data
      @repository = repository
      @user = user
      @notify_by_webhook = notify_by_webhook
      @notify_by_mail = notify_by_mail
    end

    def message_type
      porter_data["message_type"].to_s
    end

    def completed_status
      COMPLETED_STATUS_MAPPINGS[message_type]
    end

    def authors_found
      porter_data["authors_found"]
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
        "Unsupported \"message_type\" value from Porter: #{message_type}",
      )
    end

    def notify
      send_mail if notify_by_mail?
      enqueue_hook if notify_by_webhook?
    end

    def send_mail
      validate_message_type

      PorterMailer.send(
        message_type,
        repository:    repository,
        current_user:  user,
        authors_found: authors_found,
      ).deliver_later
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
