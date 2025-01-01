# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    # Mixin for the GitHub module that contains all Education configuration settings
    module Education

      # Education configuration
      attr_accessor :education_twirp_url
      attr_accessor :education_hmac_key

      # Education URL
      #
      # Returns the URL string ("https://education.github.com", "http://education.github.com/students", etc.)
      def education_url
        "https://education.github.com"
      end

      def education_bundle_documentation_url
        "https://github.com/github/education-web/blob/main/docs/architecture/education_skus.md"
      end

      def education_community_url
        "https://github.com/orgs/community/discussions/categories/github-education"
      end
    end
  end

  extend Config::Education
end
