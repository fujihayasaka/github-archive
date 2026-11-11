# typed: strict
# frozen_string_literal: true

module CodeScanning
  # This class represents an event related to a code scanning alert.
  # It is used to encapsulate some details of the event for processing
  # within the notification system.
  class AlertEventNotification
    include ::Permissions::Attributes::Wrapper
    self.permissions_wrapper_class = ::Permissions::Attributes::CodeScanning::AlertEvent

    sig { returns(Integer) }
    attr_reader :alert_number

    sig { returns(T.nilable(Repository)) }
    attr_reader :repository

    alias id alert_number # For compatibility with existing code expecting an 'id' method in the notification subject

    sig { params(alert_number: Integer, repository: Repository).void }
    def initialize(alert_number:, repository:)
      @alert_number = alert_number
      @repository = repository
    end

    sig { returns(T::Array[Authzd::Proto::Attribute]) }
    def authzd_attributes
      permissions_wrapper.serialized_subject_attributes
    end

    # The unique Message-ID header value for notifications and email.
    sig { returns(String) }
    def message_id
      "<#{T.must(repository).name_with_display_owner}/security/code-scanning/#{id}@#{GitHub.urls.host_name}>"
    end
  end
end
