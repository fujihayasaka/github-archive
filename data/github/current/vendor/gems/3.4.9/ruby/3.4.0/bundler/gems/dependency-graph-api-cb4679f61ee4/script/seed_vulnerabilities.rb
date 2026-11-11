# Rolling out manifest ingest for a new language ecosystem and integrating Dependabot Alerts on repositories hosting projects with vulnerable dependencies is a two step process:
# 1. All repositories hosting projects in the new language ecosystem must be processed by the new manifest adapter to ingest declared dependencies
# 2. Dependabot Alerts for Advisory DB vulnerabilities for the new language ecosystem must be backfilled
#
# ^ This script can be `load`ed in a monolith WRTIE console with `gh-console master` to perform step 2.
#
# Arguments:
#   actor     - the login of the DG admin running the script
#   dry_run   - boolean to log but not execute process_alerts on each vulnerability
#   delay_ms  - integer number of millis to pause between per-vuln process_alerts calls
#   skip_notifications - boolean to enable email notification during alert processing
#
# Usage:
#   Process just one alert as a production sanity-check test, or spot backfill,
#   using the AdvisoryDB ID as input:
# SeedDependabotAlerts.new(dry_run: false, delay_ms: 0, skip_notifications: false).process_one(id: 1234)
#
#   Process all advisories for a given ecosystem and severity level, in "dry run"
#   mode where no actual alerts will be published
# SeedDependabotAlerts.new(dry_run: true, delay_ms: 5000, skip_notifications: true).process_many(ecosystem: :rust, severity: :critical, from: nil)
#
#   Process all low-severity vulns (re)starting from a particular DB ID
# SeedDependabotAlerts.new(dry_run: false, delay_ms: 15000, skip_notifications: false).process_many(ecosystem: :rust, severity: :low, from: 15256)

class SeedDependabotAlerts
  def initialize(dry_run:, delay_ms:, skip_notifications:)
    @actor = ::User.staff_user
    @dry_run = dry_run
    @delay = delay_ms / 1000.0
    @skip_notifications = skip_notifications
  end

  def process_one(id:)
    @vuln_id = id.to_i

    puts "Processing vulnerability #{@vuln_id} #{"(dry run)" if @dry_run}"
    process
  end

  def process_many(ecosystem:, severity:, from:)
    @ecosystem = ecosystem
    @severity = severity
    @from = from

    puts "Processing vulnerabilities for ecosystem #{@ecosystem} of severity #{@severity} #{"from ID: " + @from.to_s if @from} #{"(dry run)" if @dry_run}"
    process
  end

  private

  def process
    count = 0
    vulns_to_process = []

    print "Fetching vulnerabilities"
    ActiveRecord::Base.connected_to(role: :reading) do
      if @vuln_id
        vulns_to_process << single_vulnerability_query
        print "."
      else
        vulnerabilities_query.find_in_batches.each do |batch|
    batch.each do |vuln|
            vulns_to_process << vuln
            print "."
    end
        end
      end
    end
    puts

    vulns_to_process.each do |vuln|
      # https://github.com/github/github/blob/d75d3116a5876ff8b9dcec20f4b43dac9b84a25f/db/notify-structure.sql#L254
      # https://github.com/github/github/blob/8fc592f794accf5ac91a197a27bd24dc6dc16e51/app/models/vulnerability.rb#L259-L266
      puts "Processing vulnerability: #{vuln.id} (#{vuln.ghsa_id}) #{vuln.identifier}"
      vuln.process_alerts(actor: @actor, skip_notifications: @skip_notifications) if !@dry_run
      count += 1
      sleep(@delay)
    end

    puts "Done! #{count} vulnerabilities processed"
  end

  def single_vulnerability_query
    ::Vulnerability.includes(:vulnerable_version_ranges).find_by_id(@vuln_id.to_i)
  end

  def vulnerabilities_query
    # TODO(eli): investigate dependency_graph_supported scope
    scope = ::Vulnerability.includes(:vulnerable_version_ranges)
    scope = scope.has_ecosystem(@ecosystem.to_s.downcase)
    scope = scope.severity(@severity.to_s.downcase)
    scope = scope.status(:published.to_s.downcase)
    scope = scope.order(id: :asc)
    scope = scope.where("vulnerabilities.id >= ?", @from) if @from

    scope
  end
end
