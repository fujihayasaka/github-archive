module Views
  class PackageReleaseVulnerabilitiesCount < ApplicationRecord
    self.table_name = "dg_package_release_vuln_counts"

    def self.rebuild
      Instrument.time("views.package_release_vulnerabilities_count") do
        existing_pr_ids = ActiveRecord::Base.connected_to(role: :reading) do
          self.distinct.pluck(:package_release_id)
        end

        # Keep a cache of package releases (id, version) by (package_manage, package_name)
        # so we don't have to look it up multiple times from the database for vulnerable
        # version ranges pertaining to the same package.
        prs_cache = {}

        counts_by_pr_id = {}
        ActiveRecord::Base.connected_to(role: :reading) do
          VulnerableVersionRange.where.not(severity: nil).find_each do |vvr|
            package_key = [vvr.package_manager, vvr.package_name]
            prs = prs_cache[package_key]
            if prs.nil?
              prs = PackageRelease.where(package_manager: vvr.package_manager, package_name: vvr.package_name).pluck(:id, :version)
              prs_cache[package_key] = prs
            end
            prs.each do |pr|
              pr_id, pr_version = pr
              if vvr.contains_version?(pr_version)
                if counts_by_pr_id[pr_id].nil?
                  counts_by_pr_id[pr_id] = { critical: 0, high: 0, moderate: 0, low: 0 }
                end
                counts_by_pr_id[pr_id][vvr.severity.to_sym] += 1
              end
            end
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            counts_by_pr_id
              .each_slice(250) do |counts_slice|
                slice = counts_slice.map do |pr_id, counts|
                  self.new(
                    package_release_id: pr_id,
                    total_count: counts.values.sum,
                    low_count: counts[:low],
                    moderate_count: counts[:moderate],
                    high_count: counts[:high],
                    critical_count: counts[:critical],
                  )
                end
                DependencyGraph.throttler.throttle(:"dependency-graph") do
                  self.import(slice, on_duplicate_key_update: :all)
                end
              end

            (existing_pr_ids - counts_by_pr_id.keys).each_slice(250) do |slice|
              DependencyGraph.throttler.throttle(:"dependency-graph") do
                self.where(package_release_id: slice).delete_all
              end
            end
          end
        end
      end
    end
  end
end
