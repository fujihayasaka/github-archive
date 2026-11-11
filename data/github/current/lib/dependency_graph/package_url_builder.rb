# typed: strict
# frozen_string_literal: true

module DependencyGraph
  class PackageUrlBuilder
    sig { params(package_manager: T.nilable(String), package_name: T.nilable(String)).returns(T.nilable(Addressable::URI)) }
    def self.external_url(package_manager:, package_name:)
      return unless package_name.present? && package_manager.present?

      case package_manager.to_s.upcase
      when "NUGET"
        Addressable::Template.new("https://www.nuget.org/packages/{package}").expand(package: package_name)
      when "PIP"
        Addressable::Template.new("https://pypi.org/project/{package}").expand(package: package_name)
      when "NPM"
        Addressable::Template.new("https://www.npmjs.com/package/{package}").expand(package: package_name)
      when "RUBYGEMS"
        Addressable::Template.new("https://rubygems.org/gems/{package}").expand(package: package_name)
      when "MAVEN"
        org_id, artifact_id = package_name.split(":")
        Addressable::Template.new("https://search.maven.org/artifact/{org_id}/{artifact_id}").expand(org_id: org_id, artifact_id: artifact_id)
      when "COMPOSER"
        Addressable::Template.new("https://packagist.org/packages/{package}").expand(package: package_name)
      end
    end
  end
end
