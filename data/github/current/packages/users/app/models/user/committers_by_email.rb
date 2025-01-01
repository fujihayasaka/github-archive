# typed: true
# frozen_string_literal: true

# Takes an Array of emails (as Strings) and returns a Hash of emails mapped to
# known Users for all those emails.
#
# Returns a Hash of String email => User (who owns the email)
class User
  class CommittersByEmail
    # Convenience Finder
    #   ... for your health!
    def self.find(emails)
      new(emails).find
    end

    def initialize(emails)
      @emails = emails
      @filtered_emails = filter_emails
    end

    # Finds the corresponding Users for specific email(s)
    #
    # Returns a Hash of String emails => User
    def find
      user_emails = find_user_emails

      user_emails.inject({}) do |hash, email|
        hash[email.email] = email.user
        hash
      end
    end

    private

    # Filter emails down to a cleaned up list of them
    def filter_emails
      emails.flatten.uniq.select { |e| GitHub::UTF8.valid_email?(e) }
    end

    # Find Array of UserEmails for the filtered_emails we have
    def find_user_emails
      user_emails = UserEmail.
        where("email IN (?)", filtered_emails).
        includes(:user)
    end

    attr_reader :emails, :filtered_emails
  end
end
