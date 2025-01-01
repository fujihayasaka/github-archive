# typed: true
# frozen_string_literal: true

module Search
  module Filters
    class LicenseFilter < ::Search::Filter

      def initialize(opts = {})
        super(opts)
        map_bool_collection
      end

      def invalid_reason
        "An invalid license was specified."
      end

      private

      def map_bool_collection
        super

        # A repo cannot have more than 1 license, so using an AND condition with separate licenses
        # like "mit AND gpl" is useless, it will return no results. So instead we're joining all
        # the licenses provided into a single OR'd list
        if bool_collection.and_should
          bool_collection.must = (bool_collection.must || []) + bool_collection.and_should.flatten
        end

        expand_families!(bool_collection.must)
        expand_families!(bool_collection.must_not)
      end

      def expand_families!(licenses)
        return unless licenses

        licenses.map! do |license|
          code_for(license.downcase)
        end

        licenses.flatten!
        licenses.compact!

        @valid = licenses.present?

        licenses
      end

      def code_for(license)
        if code = License::LICENSES_TO_IDS[license]
          code
        elsif family_licenses = licenses_in_family(license)
          family_licenses.map { |license| code_for(license) }
        else
          nil
        end
      end

      def licenses_in_family(license)
        License::LICENSE_FAMILIES[license]
      end
    end
  end
end
