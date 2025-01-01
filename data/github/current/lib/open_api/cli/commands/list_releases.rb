# typed: false
# frozen_string_literal: true

module OpenApi
  module CLI
    module Commands
      class ListReleases
        def self.list(include_unpublished:)
          releases = OpenApi::Description::Release.find_all([], include_unpublished: include_unpublished)

          releases.delete_if { |release| release.identifier == GitHub.enterprise_test_openapi_release }
          releases.delete_if { |release| release.deprecated? }
          releases.delete_if { |release| !release.published? } unless include_unpublished

          releases.each do |release|
            puts "#{release.identifier}"
          end

        end
      end
    end
  end
end
