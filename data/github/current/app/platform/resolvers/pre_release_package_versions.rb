# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class PreReleasePackageVersions < Resolvers::PackageVersions

      def filter(versions, arguments)
        versions.where(pre_release: true)
      end
    end
  end
end
