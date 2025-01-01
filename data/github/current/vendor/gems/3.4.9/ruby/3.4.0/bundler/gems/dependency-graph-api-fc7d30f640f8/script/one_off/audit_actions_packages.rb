#!/usr/bin/env ruby
# Audit actions packages and remove ones releases with invalid revisions
# Usage: script/one_off/audit_actions_packages.rb [-d] [--package=NAME]

require "optparse"
require_relative "../../config/environment"

checkpoint = Checkpoint.find_or_create_by(name: "audit_actions_packages")

options = { delete: false, specific_package: nil }
OptionParser.new do |opts|
  opts.on("-d", "--delete", "Delete invalid actions releases from database") do
    options[:delete] = true
  end

  opts.on("--package=NAME", "Audit a particular package") do |package|
    options[:specific_package] = package
  end
end.parse!

def audit_actions_packages(options, checkpoint)
  puts "starting package audit in #{options[:delete] ? 'deletion' : 'safe'} mode!"

  begin
    processed_count = 0
    deleted_count = 0
    package_manager = ActionsPackageJob.new

    ActiveRecord::Base.connected_to(role: :reading) do
      selection = options[:specific_package] ? Package.where(package_manager: Types::PackageManager[:actions], name: options[:specific_package]) : Package.where(package_manager: Types::PackageManager[:actions])
      selection.find_in_batches(batch_size: 100).each do |packages|
        packages.each do |package|
          package_name = package.name
          puts "checking #{package_name}..."

          package_repo_id = package.repository&.github_repository_id
          releases = package.releases

          releases.each do |release|
            package_version = release.name.force_encoding(Encoding::ASCII_8BIT)
            valid_version = package_manager.version_exists_in_repo?(repo_id: package_repo_id, version: package_version)

            if valid_version
              puts "#{package_name} (#{package_version}) is valid."
            else
              puts "#{package_name} (#{package_version}) is invalid and #{options[:delete] ? 'will now' : 'needs to'} be deleted."

              if options[:delete]
                ActiveRecord::Base.connected_to(role: :writing) do
                  release.destroy

                  if package.releases.count.zero?
                    package.destroy
                  end
                end
              end

              deleted_count += 1
            end
          end

          processed_count += 1
          ActiveRecord::Base.connected_to(role: :writing) { checkpoint.update(last_checkpointed_id: processed_count) }
        end
      end
    end

    puts "done auditing packages! processed #{processed_count} #{'package'.pluralize(processed_count)} and #{options[:delete] ? 'have deleted' : 'would delete'} #{deleted_count} #{'release'.pluralize(deleted_count)}."
  rescue => e
    puts "Exception!"
    Failbot.report(e)
    raise e
  end
end

Instrument.time("dg.audit_actions_packages") do
  audit_actions_packages(options, checkpoint)
end
