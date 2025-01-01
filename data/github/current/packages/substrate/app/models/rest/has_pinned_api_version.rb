# typed: false
# frozen_string_literal: true

module Rest
  module HasPinnedApiVersion
    extend ActiveSupport::Concern

    included do
      validate :pinnable_version
    end

    def pinnable_version
      # During the roll-out, allow `nil` here, to avoid breaking users that don't have this feature enabled.
      return if pinned_api_version.blank?
      unless Api::Versioning.usable_version?(pinned_api_version)
        errors.add(:pinned_api_version, "is invalid")
      end
    end

    def self.version_options_for_select
      versions = [["Unpinned", nil]]
      Api::Versioning.usable_versions.each do |api_version|
        versions << [api_version, api_version]
      end
      versions
    end
  end
end
