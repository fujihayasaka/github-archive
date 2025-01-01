# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module PackageQuery

      def self.get_package(inputs, context)
        raise Errors::Unprocessable.new("packageType is required to properly identify the package.") unless inputs[:package_type]
        owner = User.find_by_login(inputs[:owner])
        raise Errors::NotFound.new("User #{inputs[:owner]} does not exist.") unless owner
        owner.packages.with_name_and_type(inputs[:package_name], inputs[:package_type], inputs[:registry_package_type] || inputs[:package_type]) # TODO: Remove :registry_package_tag check after removing legacy mutations.
      end

      # TODO: Remove after removing legacy mutations.
      def self.check_package_read_access(inputs, context)
        registry_package = get_package(inputs, context)
        raise Errors::NotFound.new("Package does not exist.") unless registry_package

        repository = registry_package.repository
        raise Errors::NotFound.new("Package does not exist.") unless repository
        # prevent information disclosure by someone spamming us with package names
        # and try to guess if a private repository exists.
        raise Errors::NotFound.new("Package does not exist.") unless repository.resources.packages.readable_by?(context[:viewer])

        registry_package
      end

      # TODO: Remove after removing legacy mutations.
      def self.check_package_write_access(inputs, context)
        registry_package = check_package_read_access(inputs, context)
        repository = registry_package.repository
        raise Errors::NotFound.new("Package does not exist.") unless repository
        raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have write access to this repository.") unless repository.resources.packages.writable_by?(context[:viewer])

        registry_package
      end

      # Public: Removes packages that aren't visible to the current viewer.
      #
      # Currently, using the `can_access?` check inside a GraphQL field
      # When its being called from dotcom will be a no-op and return
      # true, regardless of the viewer's access.
      # This causes issues when the `async_viewer_can_see?` check for a record fails,
      # causing the dotcom route to fail.
      # This method uses the `repo.readable_by?` check so that the
      # check for dotcom is consistent.
      # We can get away with this check here, since GitHub Apps cannot browse
      # the dotcom UI.
      #
      # packages      - An enumeration of Registry::Package instances to filter.
      #
      # Returns a filtered collection of packages that are visible to the current viewer.
      def self.filter_packages_for_dotcom(packages, viewer)
        loaded_packages = packages.map do |package|
          package.async_repository.then do |repository|
            unless repository.nil?
              repository.async_organization.then do
                repository.async_readable_by?(viewer).then do |result|
                  if result
                    package
                  else
                    nil
                  end
                end
              end
            end
          end
        end

        loaded_packages
      end
    end
  end
end
