# frozen_string_literal: true

module AdvisoryDB
  module Config
    module MITRE
      def cve_api_org
        ENV.fetch("CVE_API_ORG", nil)
      end

      def cve_api_org_id
        # The following ID was obtained from a GitHub record that was converted
        # from CVE JSON 4.0 to 5.0. See https://github.com/CVEProject/cvelistV5/blob/22154857d2f19ba79cbb697c7c76fd6408f6cddb/review_set/2021/32xxx/CVE-2021-32835.json#L128
        "a0819718-46f1-4df5-94e2-005712e83aaa"
      end

      def cve_api_user
        ENV.fetch("CVE_API_USER", nil)
      end

      def cve_api_key
        ENV.fetch("CVE_API_KEY", nil)
      end

      def cve_automatic_assignment_enabled?
        ENV["FEATURE_FLAG_CVE_AUTOMATIC_ASSIGNMENT"] == "true"
      end

      def cve_automatic_reservation_enabled?
        ENV["FEATURE_FLAG_CVE_AUTOMATIC_RESERVATION"] == "true"
      end

      def cve_services_api_url
        ENV.fetch("CVE_SERVICES_API_URL")
      end
    end

    include MITRE
  end
end
