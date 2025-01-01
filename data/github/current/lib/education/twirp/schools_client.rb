# typed: true
# frozen_string_literal: true

module Education
  module Twirp
    class SchoolsClient < Education::Twirp::BaseClient
      def get_schools(github_user_verified_emails:, ip_address:)
        rpc(:GetSchools, github_user_verified_emails:, ip_address:)
      end

      def search_schools(school_name_query:, ip_address:)
        rpc(:SearchSchools, school_name_query:, ip_address:)
      end

      private

      def twirp_class
        EducationWeb::V1::SchoolsClient
      end
    end
  end
end
