# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module AdvisoryDB
      class SubmitAdvisoryProcessor < SingleMessageProcessor
        include Vulnerability::WebhookHelper
        default_to_write_connection!

        DEFAULT_GROUP_ID = "submit_advisory"
        DEFAULT_SUBSCRIBE_TO = /advisory_db.v0.SubmitAdvisory\Z/
        STATS_NAMESPACE = "advisory_db_processor.submit_advisory"

        UnprocessableAdvisory = Class.new(StandardError)

        rescue_from UnprocessableAdvisory, with: :report_unprocessable_advisory

        attr_reader :filter

        # These settings can be adjusted according to
        # https://github.com/zendesk/ruby-kafka#balancing-throughput-and-latency
        # Here we're using the defaults suggested in
        # https://github.com/github/hydro/blob/master/docs/consuming.md#deploying-a-consumer
        options[:min_bytes] = 5.megabytes
        options[:max_wait_time] = 0.2.seconds
        options[:max_bytes_per_partition] = 25.megabytes
        options[:start_from_beginning] = false

        private

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          @filter = kwargs[:filter]

          self.dead_letter_topic = "cp1-iad.ingest.advisory_db.v0.SubmitAdvisory.DeadLetter"
        end

        def process_message(message)
          if filter && !filter.call(message)
            GitHub.dogstats.increment("#{STATS_NAMESPACE}.filtered_out")
            message.skip_process
          else
            process_advisory(message.value[:advisory], message.value[:status])
          end
        end

        # Create or update a Vulnerability record based on a Hydro Advisory.
        def process_advisory(advisory, status)
          # Wrap this whole operation in a MySQL transaction so creating or
          # updating the Vulnerability and all of its associated records is an
          # all-or-nothing process.

          saved_vulnerability, range_ids_to_alert = write_class.transaction do
            # Find and modify or build a new Vulnerability record using
            # attributes from the incoming Hydro Advisory entity.
            ghsa_id = advisory[:ghsa_id]
            vulnerability = write_class_scope.find_by(ghsa_id: ghsa_id) ||
              write_class.new(ghsa_id: ghsa_id)
            # Save the current state of the advisory for determining what webhooks to send
            initial_vuln_hash = hash_of_hook_attributes(vulnerability)
            initial_vvr_ids = vulnerability.vulnerable_version_ranges.pluck(:id)
            initial_cwe_ids = vulnerability.cwe_ids

            vulnerability.assign_attributes(
              status:               status_for_advisory(advisory, status),
              classification:       advisory[:classification].to_s.downcase,
              cve_id:               advisory[:cve_id].presence,
              cvss_v3:              advisory[:cvss_v3].presence,
              cvss_v4:              advisory[:cvss_v4].presence,
              cwe_ids:              cwe_ids_for_advisory(advisory),
              description:          advisory[:description],
              npm_id:               advisory[:npm_id].present? && advisory[:npm_id].positive? ? advisory[:npm_id] : nil,
              severity:             severity_for_advisory(advisory),
              summary:              advisory[:summary].presence,
              white_source_id:      advisory[:white_source_id].presence,
              source_code_location: advisory[:source_code_location],
              published_at:         Time.at(advisory.dig(:published_at, :seconds)),
              withdrawn_at:         timestamp_for_advisory(advisory, :withdrawn_at),
              reviewed_at:          timestamp_for_advisory(advisory, :reviewed_at),
              nvd_published_at:     timestamp_for_advisory(advisory, :nvd_published_at),
            )

            if write_class == ScopedVulnerability
              vulnerability.assign_attributes(
                scope: "open_source",
                advisory_repository_id: 0,
                security_advisory_id: 0
              )
            end

            # Save the new or modified Vulnerability record.
            unless vulnerability.save
              raise UnprocessableAdvisory, vulnerability.errors.full_messages.join(", ")
            end

            if vulnerability.status == "withdrawn" && vulnerability.status_previously_changed?
              vulnerability.enqueue_deletion_of_withdrawn_alerts
            end

            # Generate a fresh list of persisted VulnerabilityReference records
            # to attach to the Vulnerability.
            vulnerability_references = Array.wrap(advisory[:references]).map do |advisory_reference|
              attributes = {
                url: advisory_reference.fetch(:url),
              }

              # Find or build a VulnerabilityReference.
              vulnerability_reference = vulnerability.vulnerability_references.find_by(attributes) ||
                vulnerability.vulnerability_references.build(attributes)

              # There are no additional attributes to assign beyond URL.

              # Save the VulnerabilityReference or complain.
              unless vulnerability_reference.save
                raise UnprocessableAdvisory, vulnerability_reference.errors.full_messages.join(", ")
              end

              vulnerability_reference
            end


            if helper.writing_to_scoped_vulnerabilities?
              # Given the fact that we defined the association with a :restrict_with_error
              # dependent option in order to avoid accidentally deleting data associated with a Vulnerability when destroying
              # a ScopedVulnerability, we need to manually delete any references that are no longer present.
              # We will be able to remove this once we transfer fully to utilizing ScopedVulnerability.
              refs_to_delete = vulnerability.vulnerability_references.where.not(id: vulnerability_references.pluck(:id))
              refs_to_delete.delete_all
            else
              # This performs a database insert to overwrite the Vulnerability's
              # references with the fresh list we generated above. This will also
              # delete any existing references that didn't make the cut.
              vulnerability.vulnerability_references = vulnerability_references
            end

            # Generate a fresh list of persisted VulnerableVersionRange records
            # to attach to the Vulnerability, and collect which ones are new in
            # order to alert on them at the end of advisory processing.
            range_ids_to_alert = []
            vulnerable_version_ranges = Array.wrap(advisory[:vulnerabilities]).map do |advisory_vulnerability|
              attributes = {
                affects: advisory_vulnerability[:package_name],
                ecosystem: ::AdvisoryDB::Ecosystems.from_advisory_vulnerability(advisory_vulnerability).name,
                requirements: advisory_vulnerability[:vulnerable_version_range],
              }

              existing_vulnerable_version_range = vulnerability.vulnerable_version_ranges.find_by(attributes)

              # Find or build a VulnerableVersionRange.
              vulnerable_version_range = existing_vulnerable_version_range ||
                vulnerability.vulnerable_version_ranges.build(attributes)

              # Assign additional attributes.
              vulnerable_version_range.assign_attributes(fixed_in: advisory_vulnerability[:first_patched_version].presence)

              # Save the VulnerableVersionRange or complain.
              unless vulnerable_version_range.save
                raise UnprocessableAdvisory, vulnerable_version_range.errors.full_messages.join(", ")
              end

              # Find all new ranges that we want to alert later
              range_ids_to_alert.push(vulnerable_version_range.reload.id) unless existing_vulnerable_version_range

              vulnerable_version_range
            end

            if helper.writing_to_scoped_vulnerabilities?
              # Given the fact that we defined the association with a :restrict_with_error
              # dependent option in order to avoid accidentally deleting data associated with a Vulnerability when destroying
              # a ScopedVulnerability, we need to manually delete any references that are no longer present.\
              # We will be able to remove this once we transfer fully to utilizing ScopedVulnerability.
              vvrs_to_delete = vulnerability.vulnerable_version_ranges.where.not(id: vulnerable_version_ranges.pluck(:id))
              vvrs_to_delete.destroy_all
            else
              # This performs a database insert to overwrite the Vulnerability's
              # vulnerable version ranges with the fresh list we generated above.
              # This will also delete any existing vulnerable version ranges that
              # didn't make the cut.
              vulnerability.vulnerable_version_ranges = vulnerable_version_ranges
            end

            # Decide if any of the VVR updates should trigger update instrumentation on the vulnerability
            vvrs_changed = initial_vvr_ids.to_set != vulnerable_version_ranges.map(&:id).to_set
            vvrs_changed ||= vulnerable_version_ranges.any? do |vvr|
              vvr.instrument_vulnerability_update?
            end

            # Instrument a Dependabot alerts upstream change event if the vulnerability has changed
            cwes_changed = initial_cwe_ids.to_set != vulnerability.cwe_ids.to_set
            instrument_dependabot_alert_upstream_change = vulnerability.previous_changes.present? || cwes_changed
            have_instrumented_change = false

            if instrument_dependabot_alert_upstream_change
              upstream_changes = vulnerability.previous_changes.keys
              upstream_changes << "cwe_ids" if cwes_changed

              have_instrumented_change = vulnerability.instrument_dependabot_alerts_upstream_change(event: :update, changes: upstream_changes)
            end

            # Instrument a Dependabot alerts upstream change event for any of the VVRs that have changed
            # Note at this time we don't care about VVRs that are added or removed, only those that have changed
            unless have_instrumented_change
              vulnerable_version_ranges.select(&:instrument_vulnerability_update?).each do |vvr|
                vvr.instrument_dependabot_alerts_upstream_change(event: :update, changes: vvr.previous_changes.keys)
              end
            end

            # Associate existing credits from the repository advisory with this vulnerability
            repository_advisory = RepositoryAdvisory.find_by(ghsa_id: ghsa_id)
            if repository_advisory
              unassociated_credits = repository_advisory.credits.where(vulnerability_id: nil)
              unassociated_credits.update_all(vulnerability_id: vulnerability.id, updated_at: Time.zone.now)
            end

            # TODO: right now this is just additive to credit advisory improvement submissions,
            # but when global advisory credits are curatable (https://github.com/github/team-advisory-database/issues/2420),
            # this will need to follow the pattern above that also removes those that didn't make the cut.
            recipient_ids = Array.wrap(advisory[:credits]).filter_map { |credit| credit[:recipient_id] }.uniq
            existing_recipient_ids = vulnerability.credits.where(recipient_id: recipient_ids).pluck(:recipient_id).to_set
            recipient_ids.each do |recipient_id|
              if !existing_recipient_ids.include?(recipient_id)
                advisory_credit = vulnerability.credits.build(recipient_id: recipient_id, creator_id: recipient_id)

                unless advisory_credit.save
                  raise UnprocessableAdvisory, advisory_credit.errors.full_messages.join(", ")
                end
              end
            end

            # Trigger alert processing for new ranges if the vulnerability is alertable
            # At this time, we want to only Vulnerability is doing the alerting until we
            # implement scoped vulnerability usage in the alerting process. In order to
            # accomplish this when we are syncing to Vulnerability instead of writing,
            # we need to process alerts in the VulnerabilityTransitionSyncJob instead.
            unless helper.writing_to_scoped_vulnerabilities?
              helper.process_alerts(vulnerability, range_ids_to_alert)
            end
            instrument_webhooks(vulnerability, initial_vuln_hash, vvrs_changed:)

            [vulnerability, range_ids_to_alert]
          end

          VulnerabilitiesTransitionSyncJob.perform_later(saved_vulnerability.id, range_ids_to_alert: range_ids_to_alert) if helper.sync_enabled? && saved_vulnerability
        end

        def cwe_ids_for_advisory(advisory)
          return [] unless advisory[:cwe_ids].present?

          cwes = CWE.where(cwe_id: advisory[:cwe_ids]).to_a
          if cwes.size != advisory[:cwe_ids].size
            raise UnprocessableAdvisory, "Missing CWEs for IDs: #{advisory[:cwe_ids] - cwes.map(&:cwe_id)}"
          end

          cwes.map(&:id)
        end

        def severity_for_advisory(advisory)
          severity = advisory[:severity]&.to_s&.downcase
          Vulnerability::SharedMethods::SEVERITIES.include?(severity) ? severity : nil
        end

        def status_for_advisory(advisory, status)
          if status == :UNREVIEWED
            :unreviewed
          elsif timestamp_for_advisory(advisory, :withdrawn_at)
            :withdrawn
          else
            :published
          end
        end

        def timestamp_for_advisory(advisory, field)
          timestamp = advisory.dig(field, :seconds)
          timestamp.present? ? Time.at(timestamp) : nil
        end

        def report_unprocessable_advisory(error)
          GitHub.dogstats.increment("#{STATS_NAMESPACE}.unprocessable")
          report_error(error)
        end

        def write_class
          if helper.writing_to_scoped_vulnerabilities?
            ScopedVulnerability
          else
            Vulnerability
          end
        end

        def write_class_scope
          if helper.writing_to_scoped_vulnerabilities?
            ScopedVulnerability.open_source
          else
            Vulnerability
          end
        end

        def helper
          ::AdvisoryDB::ScopedVulnerabilityHelper
        end

        def error_context_for_message(message)
          super(message).merge({
            "ghsa_id" => message.value.dig(:advisory, :ghsa_id)
          })
        end
      end
    end
  end
end
