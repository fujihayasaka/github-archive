require "table_swap"

class VulnerableVersionRange < ApplicationRecord
  self.table_name = "dg_vulnerable_version_ranges"

  restrict_type_of :package_manager, to: Types::PackageManager

  def self.sync
    Sync.run
  end

  def self.for_package_manager(package_manager)
    where(package_manager: package_manager.serialize)
  end

  def self.for_package(package_name)
    where(package_name: package_name)
  end

  def requirements_set
    @requirements_set ||= Versioning::RequirementSet
      .deserialize(version_range, allow_named_versions: allows_named_versions?)
  end

  def contains_version?(version)
    requirement = Versioning::RequirementSet.deserialize("= #{version}", allow_named_versions: allows_named_versions?)
    requirements_set.contain?(requirement)
  end

  def allows_named_versions?
    Types::PackageManager.allows_named_versions?(package_manager)
  end

  class Sync
    def self.run
      new.run
    end

    def run
      start = Time.now

      Instrument.time("jobs.sync_vulnerabilities") do
        begin
          GitHubVulnerableVersionRange.published.preload(:vulnerability).in_batches(of: 1000) do |batch|
            ranges = batch.map do |range|
              next if (range.vulnerability.nil? || !range.requirement_set.valid? || range.ecosystem.blank? || range.package_manager.nil?)

              VulnerableVersionRange.new({
                github_id:           range.id,
                severity:            range.vulnerability.severity,
                package_name:        range.affects,
                package_manager:     range.package_manager,
                version_range:       range.requirement_set.serialize,
                encoded_lower_bound: range.requirement_set.encoded_lower_bound || 0, #TODO: These encoded bounds cannot be null. We need to see if it'll be a problem
                encoded_upper_bound: range.requirement_set.encoded_upper_bound || 0,
              })
            end

            VulnerableVersionRange.import(ranges.compact, {
              on_duplicate_key_update: [
                :severity,
                :package_name,
                :package_manager,
                :version_range,
                :encoded_lower_bound,
                :encoded_upper_bound,
                :updated_at,
              ]
            })
          end

          VulnerableVersionRange.where("updated_at < ?", Time.at(start.to_i)).destroy_all
        rescue => e
          Instrument.increment("jobs.sync_vulnerabilities.error")
          # It's confusing, but this function is only called from the SyncVulnerabilitiesJob, even though it is not a job itself.
          Failbot.report(e, "gh.aqueduct.job.name" => "sync_vulnerabilities")
          # rethrow the error so that the job fails.
          raise e
        end
      end
    end
  end

  class ParseError < RuntimeError
    def initialize(requirements, version_range)
      @requirements  = requirements
      @version_range = version_range
    end

    def message
      "Invalid version range '#{@requirements}'. Context #{context.to_yaml}"
    end

    def context
      {
        id:               @version_range.id,
        affects:          @version_range.affects,
        version_range:    @version_range.version_range,
        vulnerability_id: @version_range.vulnerability_id,
        description:      @version_range.vulnerability.description,
      }
    end
  end

  class NotifyModel < ApplicationRecord
    self.abstract_class = true

    establish_connection(Rails.configuration.database_configuration.fetch("github_notify").fetch(Rails.env))

    # DepGraph should never write to the real notify tables
    def readonly?
      !["test", "development"].include?(Rails.env)
    end
  end

  class GitHubVulnerability < NotifyModel
    self.table_name = "vulnerabilities"

    has_many :vulnerable_version_ranges,
      class_name: "GitHubVulnerableVersionRange",
      foreign_key: :vulnerability_id

    scope :published, -> { where(status: "published") }
  end

  class GitHubVulnerableVersionRange < NotifyModel
    self.table_name = "vulnerable_version_ranges"

    belongs_to :vulnerability,
      class_name:  "GitHubVulnerability",
      foreign_key: :vulnerability_id

    scope :published, -> { joins(:vulnerability).merge(GitHubVulnerability.published) }

    def package_manager
      begin
        Types::PackageManager.coerce(ecosystem.to_s.downcase)
      rescue ArgumentError
        # Since the AdvisoryDB supports advisory ecosystems that Dependency Graph doesn't we need to capture
        # ArgumentErrors that happen on a failed `coerce`. We'll skip nil package_managers in import.
        nil
      end
    end

    def version_range
      if lower_bound? || upper_bound?
        range = []
        range << ">= #{lower_bound}" if lower_bound?
        range << "<= #{upper_bound}" if upper_bound?
        range.join(",")
      else
        attributes["requirements"]
      end
    end

    def lower_bound
      attributes["lower_bound"]
    end

    def lower_bound?
      lower_bound.present?
    end

    def upper_bound
      attributes["upper_bound"]
    end

    def upper_bound?
      upper_bound.present?
    end

    def requirement_set
      @requirement_set ||= Versioning::RequirementSet
        .deserialize(version_range, **{
          on_error: ->(requirements) {
            Failbot.report(ParseError.new(requirements, self))
          },
          allow_named_versions: Types::PackageManager.allows_named_versions?(package_manager),
        })
    end
  end
end
