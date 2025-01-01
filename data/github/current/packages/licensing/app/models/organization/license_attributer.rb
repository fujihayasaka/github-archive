# typed: true
# frozen_string_literal: true

class Organization
  class LicenseAttributer
    def initialize(organization)
      @organization = organization
    end

    def user_ids
      @_user_ids ||= license_holder.users.values.to_set
    end

    def emails
      @_emails ||= license_holder.emails.values.to_set
    end

    def unique_count
      user_ids.count + emails.count
    end

    private

    attr_reader :organization

    def license_holder
      @_license_holder ||= LicenseHolder.new(organization)
    end
  end
end
