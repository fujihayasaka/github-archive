# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module AdvisoryDB
      class CVERequestResponseProcessor < BaseProcessor
        default_to_write_connection!

        Error = Class.new(StandardError)
        AdvisoryNotFoundError = Class.new(Error)
        RepositoryNotFoundError = Class.new(Error)
        DecisionUnknownError = Class.new(Error)
        AssignedCVEIDBlankError = Class.new(Error)
        CVEIDAlreadySetError = Class.new(Error)
        AdvisoryInvalidError = Class.new(Error)

        options.update(
          start_from_beginning: false,
        )

        private

        def setup(**kwargs)
          options[:group_id] ||= "cve_request_response"
          options[:subscribe_to] ||= %r{advisory_db\.v0\.CVERequestResponse\Z}

          self.dead_letter_topic = "cp1-iad.ingest.advisory_db.v0.CVERequestResponse.DeadLetter"
        end

        def process_message(message)
          start_time = GitHub::Dogstats.monotonic_time
          payload = message.value
          tags = ["decision:#{payload[:decision]}"]
          result = "error"

          begin
            find_and_update_advisory(payload)
            result = "success"
          rescue Error => error
            Failbot.report(error)
            tags << "error:#{T.must(error.class.name).demodulize.underscore}"
          ensure
            tags << "result:#{result}"
            GitHub.dogstats.timing_since("advisory_db.cve_request_response_processor.process_time", start_time, tags: tags)
          end
        end

        def find_and_update_advisory(payload)
          advisory = RepositoryAdvisory.find_by(ghsa_id: payload[:ghsa_id])

          if advisory.nil?
            raise AdvisoryNotFoundError, "RepositoryAdvisory not found for GHSA ID: #{payload[:ghsa_id].inspect}"
          end

          if advisory.repository.nil?
            raise RepositoryNotFoundError, "Repository not found for GHSA ID: #{payload[:ghsa_id].inspect}"
          end

          advisory.with_lock do
            case payload[:decision]
            when :ASSIGNED
              apply_response(advisory, payload)
            when :NOT_ASSIGNED
              deny_request(advisory, payload)
            else
              raise DecisionUnknownError, "Decision unknown (#{payload[:decision].inspect}) for GHSA ID: #{advisory.ghsa_id}"
            end
          end
        end

        def apply_response(advisory, payload)
          if payload[:assigned_cve_id].blank?
            raise AssignedCVEIDBlankError, "Assigned CVE ID blank for GHSA ID: #{advisory.ghsa_id}"
          end

          if advisory.cve_id?
            raise CVEIDAlreadySetError, "CVE ID already set for GHSA ID: #{advisory.ghsa_id}"
          end

          advisory.cve_id = payload[:assigned_cve_id]

          if advisory.invalid?
            raise AdvisoryInvalidError, <<~ERR
              Advisory invalid for GHSA ID: #{advisory.ghsa_id}
              #{advisory.errors.full_messages.join("\n")}
              ERR
          end

          advisory.save!
          advisory.add_cve_assigned_event(comment: payload[:comment])
          advisory.reset_cve_request
        end

        def deny_request(advisory, payload)
          advisory.add_cve_not_assigned_event(comment: payload[:comment])
          advisory.reset_cve_request
        end
      end
    end
  end
end
