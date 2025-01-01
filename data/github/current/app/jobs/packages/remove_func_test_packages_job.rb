# typed: false
# frozen_string_literal: true
#
# This job cleans up test packages from the 'sweethaven-village' test org that are created by
# the Registry integration tests.
# It runs once per week.
# It does not run in enterprise.

module Packages
  class RemoveFuncTestPackagesJob < ApplicationJob
    default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

    queue_as :remove_func_test_packages

    schedule interval: 7.days, condition: -> { !GitHub.enterprise? }

    retry_on_dirty_exit

    def perform(batch_size: 100, duration: 60, offset: 0)
      # These packages are expected to exist by Container Registry integration tests and should be exempt from cleanup
      special_public_package = "packages/public-1589907775"
      special_private_package = "packages/private-1589907775"

      end_at = Time.current + duration

      meta = PackageRegistry::Twirp::MetadataClient.new
      offset = 0
      batch = 1

      loop do
        # get all the packages for our integration test namespace
        pkgs_batch = meta.get_all_packages(namespace: "sweethaven-village", exclude_deleted: true, limit: batch_size, offset: offset)
        return if pkgs_batch.empty?

        # delete the ones created by our integration tests
        pkgs_batch.each do |pkg|
          if pkg.name =~ /packages\/(?:public|private)-\d{10}/ && pkg.name != special_public_package && pkg.name != special_private_package
            meta.delete_package(ecosystem: pkg.ecosystem,
                            namespace: pkg.namespace,
                            name: pkg.name,
                            actor: User.find_by(id: pkg.author_id),
                            mode: :permanent)
          end
          GitHub.logger.info(
            "code.function" => __method__,
            "code.namespace" => self.class.name,
            "gh.registry.package_name" => pkg.name,
            "gh.registry.package_namespace" => pkg.namespace,
            "gh.registry.package_ecosystem" => pkg.ecosystem,
            "gh.registry.batch" => batch,
          )
          GitHub.dogstats.increment("packages.removetestpkgs.deleted_packages")
        end

        return if pkgs_batch.size <= 100

        offset = pkgs_batch.last.id
        batch += 1

        if Time.current >= end_at
          RemoveFuncTestPackagesJob.perform_later(batch_size, duration, offset: offset)
          break
        end
      end
    end
  end
end
