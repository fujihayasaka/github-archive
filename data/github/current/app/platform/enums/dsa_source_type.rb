
# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class DsaSourceType < Platform::Enums::Base
      description "Represents source type that discovered the Digital Services Act (DSA) violation"
      visibility :internal

      value "DSA_REPORT", description: "Directly reported as a violation of the DSA", value: :DSA_REPORT
      value "USER_REPORT", description: "Reported by a non-staff GitHub user", value: :USER_REPORT
      value "SCAN_DETECTION", description: "Detected by GitHub's abuse scanning systems", value: :SCAN_DETECTION
      value "STAFF_DETECTION", description: "Reported by a member of GitHub staff", value: :STAFF_DETECTION
    end
  end
end
