# frozen_string_literal: true

# BackfillImporter is a special importer that can be used for one-time imports and backfills
#
# The basic idea of BackfillImporter is that a set of yaml files are prepared which contain some advisory data
# Then a curator manually runs BackfillImporter and imports the advisory data from the yaml files
#
# The yaml data taken from the yaml is a complete "importer object", it has the following structure
#
#         ---
#        identifier: backfill/go-CVE-2021-21237
#        ghsa_id:
#        cve_id: CVE-2021-21237
#        npm_id:
#        advisory_payload:
#          cwe_ids:
#          - CWE-94
#          cvss_v3: CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:L/A:L
#          cvss_v4: CVSS:4.0/AV:L/AC:L/AT:P/PR:N/UI:A/VC:L/VI:H/VA:L/SC:L/SI:H/SA:L
#          summary: Arbitrary Code Execution
#          references:
#          - https://github.com/git-lfs/git-lfs/commit/fc664697ed2c2081ee9633010de0a7f9debea72a
#          - https://github.com/git-lfs/git-lfs/releases/tag/v2.13.2
#          vulnerabilities:
#            0:
#              ecosystem: go
#              package_name: github.com/git-lfs/git-lfs/creds
#              vulnerable_version_range: "< 2.13.2"
#              first_patched_version: 2.13.2
#        raw_payload:
#          version: 1
#
#
# Basically, BackfillImporter lets you import _anything_.
# It simply requires the imported data be formatted in a specific way to match what is expected by ApplicationImporter.
#
class BackfillImporter < ApplicationImporter
  disable_auto_import

  attr_reader :feed_entries_directory, :feed_entry_yaml_files

  def initialize(feed_entries_directory: "backfill")
    @feed_entries_directory = feed_entries_directory

    unless Dir.exist? feed_entries_directory
      raise ArgumentError, "Not a directory: #{feed_entries_directory}"
    end

    @feed_entry_yaml_files = Dir["#{feed_entries_directory}/*.yaml", "#{feed_entries_directory}/*.yml"]
    raise ArgumentError, "No .yaml or .yml files in directory: #{feed_entries_directory}" if feed_entry_yaml_files.empty?
  end

  def importer_objects
    feed_entry_yaml_files.map { |yaml_filename| YAML.load_file(yaml_filename).deep_symbolize_keys }
  end

  def each(&)
    importer_objects.each(&)
  end
end
