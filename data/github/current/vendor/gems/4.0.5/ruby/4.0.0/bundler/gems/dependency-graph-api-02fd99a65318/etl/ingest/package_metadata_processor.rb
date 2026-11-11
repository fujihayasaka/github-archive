# frozen_string_literal: true

module Ingest
  class PackageMetadataProcessor < Processor
    NAMESPACED_ECOSYSTEMS = %w(maven npm composer go)
    OSPO_DG_SUPPORTED_ECOSYSTEMS = %w(crate composer npm gem nuget pypi maven go)

    # legacy limit in DG-API data model :(
    MAX_SPDX_LICENSE_LENGTH = 250

    def initialize(name: "package_metadata", debug: false)
      super
    end

    def get_processor_specific_logging_context(hydro_message)
      {
        ospo_type: hydro_message.value.dig(:coordinates, :type),
      }
    rescue => e
      DependencyGraph.logger.error("Encountered error while retrieving ospo_type for logging context", e)
      Failbot.report(e)

      {}
    end

    def consume_message(message)
      Instrument.increment("etl.ospo.event.consumed")

      if validation_error = validate(message)
        Instrument.increment("etl.ospo.ingest.validation_error")
        raise OspoValidationError.new(validation_error)
      end

      event = message.value.with_indifferent_access
      ospo_type = event.dig(:coordinates, :type)
      if OSPO_DG_SUPPORTED_ECOSYSTEMS.exclude?(ospo_type)
        Instrument.increment("etl.ospo.ingest.unsupported_package_manager", type: ospo_type)
        return
      end

      package = PackageMetadataProcessor.create_package_release(event)

      # with "persist_data: true", potentially destructive (over)writes to the DG package tables are enabled!
      LoadPackageMetadataJob.perform_later(package, persist_data: true)
      Instrument.increment("etl.ospo.ingest.job_submitted", type: ospo_type)
    end

    def consume_debug_message(hydro_message)
      debug_message = {
        key: hydro_message.key,
        partition: hydro_message.partition,
        offset: hydro_message.offset,
        package_coordinates: hydro_message.value.with_indifferent_access[:coordinates].to_s,
      }

      puts debug_message
    end

    # Given a string from an OSPO release event, return the corresponding Types::PackageManager (if any)
    def self.ospo_type_to_package_manager(ospo_type)
      # TODO: "go" type+provider are tracked in OSPO source topic, can revisit - overlaps with MA/PMA atm
      case ospo_type
      when "crate"
        Types::PackageManager[:rust]
      when "composer"
        Types::PackageManager[:composer]
      when "npm"
        Types::PackageManager[:npm]
      when "gem"
        Types::PackageManager[:rubygems]
      when "nuget"
        Types::PackageManager[:nuget]
      when "pypi"
        Types::PackageManager[:pip]
      when "maven"
        Types::PackageManager[:maven]
      when "go"
        Types::PackageManager[:go]
      end
    end

    # Returns an error string if the message is missing any keys that we need to create a PackageRelease.
    # This isn't meant to prove that every field is well formed.
    def validate(hydro_message)
      event = hydro_message.value.with_indifferent_access
      DependencyGraph.logger.info("Processing package event data",
        "gh.dependency_graph.package_manager" => event.dig(:coordinates, :type),
        "gh.dependency_graph.package.namespace" => event.dig(:coordinates, :namespace),
        "gh.dependency_graph.package.name" => event.dig(:coordinates, :name),
        "gh.dependency_graph.package.version" => event.dig(:coordinates, :revision)
      )
      strings = [[:coordinates, :type], [:coordinates, :name], [:coordinates, :revision]]
      hashes = [[:uris], [:score]]
      strings.each do |ks|
        value = event.dig(*ks)
        return "message was missing #{ks.join(".")}" unless value.is_a?(String) && value.present?
      end
      hashes.each do |ks|
        value = event.dig(*ks)
        return "message was missing #{ks.join(".")}" unless value.is_a?(Hash)
      end
      nil
    end

    # Try 'repository' URL first if matches 'github.com' or fall back to home_url sources
    def self.source_url(message)
      repository = message.dig(:uris, :repository)
      return repository if repository.start_with?("https://github.com/")

      home_url(message)
    end

    # Try 'project_website' and then 'issue_tracker' URLs if present and matching 'github.com'
    def self.home_url(message)
      site = message.dig(:uris, :project_website)
      return site if site.start_with?("https://github.com/")

      tracker = message.dig(:uris, :issue_tracker)
      tracker if tracker.start_with?("https://github.com/")
    end

    # In OSPO backfill, this accounted for 382 pkgs out of 21 million.
    # TODO: fix this corner case in snapshots :(
    def self.resolve_license(message)
      license = message[:license_spdx_expression]
      if license.present? && license.length >= MAX_SPDX_LICENSE_LENGTH
        DependencyGraph.logger.info("Package license string too long",
          "gh.dependency_graph.package_manager" => message.dig(:coordinates, :type),
          "gh.dependency_graph.package.namespace" => message.dig(:coordinates, :namespace),
          "gh.dependency_graph.package.name" => message.dig(:coordinates, :name),
          "gh.dependency_graph.package.version" => message.dig(:coordinates, :revision),
        )
        Instrument.increment("etl.ospo.ingest.validation_error", reason: "license_truncated", type: message.dig(:coordinates, :type) || "unknown")

        # punt for now, no way to persist SPDX compliant indication of fail reason
        return "NOASSERTION"
      end

      license
    end

    def self.should_ignore_namespace(namespace, ospo_type)
      return NAMESPACED_ECOSYSTEMS.exclude?(ospo_type) || namespace.blank? || namespace == "-"
    end

    def self.resolve_package_name(message)
      name = message.dig(:coordinates, :name)
      ospo_type = message.dig(:coordinates, :type)
      namespace = message.dig(:coordinates, :namespace)

      return name if should_ignore_namespace(namespace, ospo_type)

      if ospo_type == "go"
        namespace = CGI.unescape(namespace)
      end

      delimiter = case ospo_type
                  when "maven"
                    ":"
                  when "npm", "composer", "go"
                    "/"
                  else
                    raise OspoValidationError.new("Unhandled namespaced type: #{ospo_type} for pkg namespace=#{namespace} name=#{name}")
                  end

      "#{namespace}#{delimiter}#{name}"
    end

    def self.create_package_release(message)
      resolved_license = resolve_license(message)
      resolved_published_at = (Time.at(message[:release_date]["seconds"]).utc.strftime("%F %T")) if message[:release_date]
      ospo_type = message.dig(:coordinates, :type)
      namespace = message.dig(:coordinates, :namespace)

      namespace = nil if should_ignore_namespace(namespace, ospo_type)

      fields = {
        package_manager: PackageMetadataProcessor.ospo_type_to_package_manager(ospo_type),
        package_name: resolve_package_name(message),
        version: message.dig(:coordinates, :revision),
        namespace: namespace,
        source_url: source_url(message),
        home_url: home_url(message),
        license: resolved_license,
        published_at: resolved_published_at,
        clearly_defined_score: message.dig(:score, :total),
        attributions: message.dig(:attributions),
      }.filter_map { |k, v| [k, v] if v.present? }.to_h
      Packages::PackageRelease.new(
        **fields
      )
    end
  end

  class OspoValidationError < ArgumentError; end
end
