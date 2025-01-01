# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

require "json"

module GitRPC
  class Client
    # Public: Get sha1sum of the audit log
    #
    # Returns the sha1sum as a string, or an error string in a form
    # convenient to dgit-diagnose.
    def sha1sum_audit_log
      send_message(:sha1sum_audit_log)
    end

    # Public: Get the time of the last line of the audit log
    #
    # Returns a Time object, or raises GitRPC::CommandFailed.
    def last_audit_log_time
      send_message(:last_audit_log_time)
    end
  end
end
