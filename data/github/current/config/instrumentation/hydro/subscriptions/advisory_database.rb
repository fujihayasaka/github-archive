# typed: true
# frozen_string_literal: true

# Events related to /advisories. Note there are two different sources that we
# subscribe to in this file: `GlobalInstrumenter`, and `GitHub`.

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("epss_ingestion.issue_ingestion_batch") do |payload|
    message = {
      source_of_ingest: payload[:source_of_ingest],
      records_to_ingest: payload[:records_to_ingest],
      ingest_for_date: payload[:ingest_for_date],
    }

    publish(message, schema: "advisory_db.v0.EPSSIngest", publisher: GitHub.sync_hydro_publisher)
  end

  subscribe("repository_advisory.create") do |payload|
    repository_advisory = payload[:repository_advisory]
    repo = repository_advisory.repository

    begin
      message = {
        request_context: serializer.request_context(GitHub.context.to_hash),
        author: serializer.user(repository_advisory.author),
        repository: serializer.repository(repo),
        repository_owner: serializer.user(repo.owner),
        repository_advisory: serializer.repository_advisory(repository_advisory),
      }

      publish(message, schema: "github.v1.RepositoryAdvisoryCreate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
    rescue => e
      GitHub.logger.error(
        "Advisory database Hydro subscriber error",
        "subscription" => "repository_advisory.create",
        "schema" => "github.v1.RepositoryAdvisoryCreate",
        "ghsa_id" => repository_advisory.ghsa_id,
        "repo" => repo&.name_with_display_owner,
        "exception_class" => e.class.name,
        "exception_message" => e.message,
      )
      # Re-raise so dev/test surfaces the error and Failbot still captures it in production
      # (EventForwarder#subscribe silently swallows in prod after reporting to Failbot).
      raise
    end
  end

  subscribe("repository_advisory.publish") do |payload|
    repository_advisory = payload[:repository_advisory]
    repo = repository_advisory.repository
    current_schema = "github.v1.RepositoryAdvisoryPublish"

    begin
      message = {
        request_context: serializer.request_context(GitHub.context.to_hash),
        actor: serializer.user(payload[:actor]),
        repository: serializer.repository(repo),
        repository_owner: serializer.user(repo.owner),
        repository_advisory: serializer.repository_advisory(repository_advisory),
      }

      result = publish(message, schema: "github.v1.RepositoryAdvisoryPublish", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat

      unless result.success?
        GitHub.logger.error(
          "Advisory database Hydro publish failed",
          "subscription" => "repository_advisory.publish",
          "schema" => "github.v1.RepositoryAdvisoryPublish",
          "ghsa_id" => repository_advisory.ghsa_id,
          "repo" => repo&.name_with_display_owner,
          "exception_class" => result.error.class.name,
          "exception_message" => result.error.message,
        )
      end

      curation_result = publish(
        {
          actor: serializer.user(payload[:actor]),
          repository_advisory_content: serializer.repository_advisory_content(repository_advisory),
        },
        schema: "advisory_db.v0.RepositoryAdvisoryCurationRequest", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }, # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
      )

      current_schema = "advisory_db.v0.RepositoryAdvisoryCurationRequest"
      unless curation_result.success?
        GitHub.logger.error(
          "Advisory database Hydro publish failed",
          "subscription" => "repository_advisory.publish",
          "schema" => "advisory_db.v0.RepositoryAdvisoryCurationRequest",
          "ghsa_id" => repository_advisory.ghsa_id,
          "repo" => repo&.name_with_display_owner,
          "exception_class" => curation_result.error.class.name,
          "exception_message" => curation_result.error.message,
        )
      end
    rescue => e
      GitHub.logger.error(
        "Advisory database Hydro subscriber error",
        "subscription" => "repository_advisory.publish",
        "schema" => current_schema,
        "ghsa_id" => repository_advisory.ghsa_id,
        "repo" => repo&.name_with_display_owner,
        "exception_class" => e.class.name,
        "exception_message" => e.message,
      )
      raise
    end
  end

  subscribe("repository_advisory.request_cve") do |payload|
    repository_advisory = payload[:repository_advisory]
    repo = repository_advisory.repository

    begin
      message = {
        actor: serializer.user(payload[:actor]),
        repository_advisory: serializer.repository_advisory(repository_advisory),
        title: repository_advisory.title,
        description: repository_advisory.description,
        cve_id: repository_advisory.cve_id,
        cvss_v3: repository_advisory.cvss_v3,
        cvss_v4: repository_advisory.cvss_v4,
        affected_products: repository_advisory.affected_products.map do |affected_product|
          {
            package_ecosystem: affected_product.ecosystem,
            package_name: affected_product.package,
            vulnerable_version_range: affected_product.affected_versions,
            first_patched_version: affected_product.patches,
          }
        end
      }

      publish(message, schema: "advisory_db.v0.CVERequest", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
    rescue => e
      GitHub.logger.error(
        "Advisory database Hydro subscriber error",
        "subscription" => "repository_advisory.request_cve",
        "schema" => "advisory_db.v0.CVERequest",
        "ghsa_id" => repository_advisory.ghsa_id,
        "repo" => repo&.name_with_display_owner,
        "exception_class" => e.class.name,
        "exception_message" => e.message,
      )
      # Re-raise so dev/test surfaces the error and Failbot still captures it in production
      # (EventForwarder#subscribe silently swallows in prod after reporting to Failbot).
      raise
    end
  end

  subscribe("repository_advisory.update") do |payload|
    repository_advisory = payload[:repository_advisory]
    repo = repository_advisory.repository

    begin
      message = {
        request_context: serializer.request_context(GitHub.context.to_hash),
        actor: serializer.user(repository_advisory.author),
        repository: serializer.repository(repo),
        repository_owner: serializer.user(repo.owner),
        repository_advisory: serializer.repository_advisory(repository_advisory),
      }

      publish(message, schema: "github.v1.RepositoryAdvisoryUpdate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat

      if payload[:request_curation]
        publish(
          {
            actor: serializer.user(payload[:actor]),
            repository_advisory_content: serializer.repository_advisory_content(repository_advisory),
          },
          schema: "advisory_db.v0.RepositoryAdvisoryCurationRequest", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }, # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
        )
      end
    rescue => e
      GitHub.logger.error(
        "Advisory database Hydro subscriber error",
        "subscription" => "repository_advisory.update",
        "schema" => "github.v1.RepositoryAdvisoryUpdate",
        "ghsa_id" => repository_advisory.ghsa_id,
        "repo" => repo&.name_with_display_owner,
        "exception_class" => e.class.name,
        "exception_message" => e.message,
      )
      raise
    end
  end

  subscribe("repository_advisory.workspace_open") do |payload|
    repository_advisory = payload[:repository_advisory]
    repo = repository_advisory.repository

    begin
      message = {
        request_context: serializer.request_context(GitHub.context.to_hash),
        actor: serializer.user(payload[:actor]),
        repository: serializer.repository(repo),
        repository_owner: serializer.user(repo.owner),
        repository_advisory: serializer.repository_advisory(repository_advisory),
        workspace: serializer.repository(repository_advisory.workspace_repository),
      }

      publish(message, schema: "github.v1.RepositoryAdvisoryWorkspaceOpen", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
    rescue => e
      GitHub.logger.error(
        "Advisory database Hydro subscriber error",
        "subscription" => "repository_advisory.workspace_open",
        "schema" => "github.v1.RepositoryAdvisoryWorkspaceOpen",
        "ghsa_id" => repository_advisory.ghsa_id,
        "repo" => repo&.name_with_display_owner,
        "exception_class" => e.class.name,
        "exception_message" => e.message,
      )
      raise
    end
  end

  subscribe("security_advisory.show") do |payload|
    begin
      security_advisory = SecurityAdvisory.find(payload.fetch(:security_advisory_id))

      message = {
        request_context: serializer.request_context(GitHub.context.to_hash),
        actor: serializer.user(payload[:actor]),
        security_advisory: security_advisory.hydro_entity_payload,
      }
      publish(message, schema: "github.v1.SecurityAdvisoryShow")
    rescue => e
      GitHub.logger.error(
        "Advisory database Hydro subscriber error",
        "subscription" => "security_advisory.show",
        "schema" => "github.v1.SecurityAdvisoryShow",
        "security_advisory_id" => payload[:security_advisory_id],
        "exception_class" => e.class.name,
        "exception_message" => e.message,
      )
      raise
    end
  end

  subscribe("vulnerability_alerting_event.save") do |payload|
    publish(payload, schema: "advisory_db.v0.AdvisoryAlertingEvent")
  end
end

Hydro::EventForwarder.configure(source: GitHub) do
  subscribe("security_advisory.publish") do |payload|
    begin
      security_advisory = AdvisoryDB::ScopedVulnerabilityHelper.get_hydro_security_advisory(payload.fetch(:security_advisory_id))
      next unless security_advisory.disclosed?

      message = { security_advisory: security_advisory.hydro_entity_payload }
      publish(message, schema: "github.v1.SecurityAdvisoryPublish", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
    rescue => e
      GitHub.logger.error(
        "Advisory database Hydro subscriber error",
        "subscription" => "security_advisory.publish",
        "schema" => "github.v1.SecurityAdvisoryPublish",
        "security_advisory_id" => payload[:security_advisory_id],
        "exception_class" => e.class.name,
        "exception_message" => e.message,
      )
      raise
    end
  end

  subscribe("security_advisory.update") do |payload|
    begin
      security_advisory = AdvisoryDB::ScopedVulnerabilityHelper.get_hydro_security_advisory(payload.fetch(:security_advisory_id))
      next unless security_advisory.disclosed?

      message = { security_advisory: security_advisory.hydro_entity_payload }
      publish(message, schema: "github.v1.SecurityAdvisoryUpdate", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
    rescue => e
      GitHub.logger.error(
        "Advisory database Hydro subscriber error",
        "subscription" => "security_advisory.update",
        "schema" => "github.v1.SecurityAdvisoryUpdate",
        "security_advisory_id" => payload[:security_advisory_id],
        "exception_class" => e.class.name,
        "exception_message" => e.message,
      )
      raise
    end
  end

  subscribe("security_advisory.withdraw") do |payload|
    begin
      security_advisory = AdvisoryDB::ScopedVulnerabilityHelper.get_hydro_security_advisory(payload.fetch(:security_advisory_id))
      next unless security_advisory.disclosed?

      message = { security_advisory: security_advisory.hydro_entity_payload }
      publish(message, schema: "github.v1.SecurityAdvisoryWithdraw", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
    rescue => e
      GitHub.logger.error(
        "Advisory database Hydro subscriber error",
        "subscription" => "security_advisory.withdraw",
        "schema" => "github.v1.SecurityAdvisoryWithdraw",
        "security_advisory_id" => payload[:security_advisory_id],
        "exception_class" => e.class.name,
        "exception_message" => e.message,
      )
      raise
    end
  end
end
