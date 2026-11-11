# typed: true
# frozen_string_literal: true

require_relative "./operation_owners"

module OpenApi
  module CLI
    module Commands
      class VerifyRootFiles < Command

        def run(release_identifiers = [])
          releases = OpenApi::Description::Release.find_all(release_identifiers, include_unpublished: true)

          releases.delete_if { |release| release.identifier == GitHub.enterprise_test_openapi_release }

          success = T.let(true, T::Boolean)

          releases.each do |release|
            current_release = YAML.safe_load(ERB.new(File.read(OpenApi.root.join("#{release.identifier}.yaml"))).result)

            if release.content == current_release
              $stderr.puts "✅ Release #{release.identifier} is up to date"
            else
              $stderr.puts "❌ Release #{release.identifier} should be regenerated"
              success = false
            end
          end

          current_contents = File.read(OpenApi.root.join("operation-owners.yaml"))
          operations_owner_payload = OpenApi::CLI::Operations::get_operation_owners_payload(releases)
          operation_owners_yaml = YAML.dump(operations_owner_payload)

          if current_contents == operation_owners_yaml
            $stderr.puts "✅ Operation owners cache is up to date"
          else
            $stderr.puts "❌ Operation owners cache should be regenerated"
            success = false
          end

          success
        end
      end
    end
  end
end
