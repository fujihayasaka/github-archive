# frozen_string_literal: true

module AdvisoryDB
  module AdvisoryPayloadConverter
    def self.upsert_structured_payload_for_advisory_payload(advisory_review, dry_run: true, logger: nil)
      if dry_run && logger.blank?
        raise "Logger must provided if dry_run is set to true"
      end

      ap = advisory_review.advisory_payload
      sap = advisory_review.structured_advisory_payload || (advisory_review.structured_advisory_payload = StructuredAdvisoryPayload.new)

      sap.summary = ap["summary"]
      sap.description = ap["description"]
      sap.source_code_location = ap["source_code_location"]
      sap.severity = ap["severity"]
      sap.cvss_v3 = ap["cvss_v3"]
      sap.cvss_v4 = ap["cvss_v4"]
      sap.withdrawn = ap["withdrawn"] || false

      if dry_run
        logger.call("Dry run would've created #{sap}")
      else
        sap.save!
      end

      indexed_upsert_rectifier(dry_run, "cwe_ids", -> { sap.cwe_ids }, lambda do |indexes_upserted|
        ap["cwe_ids"]&.each_with_index do |cwe_id, i|
          to_upsert = sap.cwe_ids.find_by(index: i) || StructuredAdvisoryPayloadCWEID.new(advisory_payload_id: sap.id, index: i)
          to_upsert.cwe_id = cwe_id
          indexes_upserted << i
          if dry_run
            logger.call("Dry run would've upserted cwe_id #{cwe_id}")
          else
            to_upsert.save!
          end
        end
      end)

      indexed_upsert_rectifier(dry_run, "references", -> { sap.references }, lambda do |indexes_upserted|
        ap["references"]&.each_with_index do |ref, i|
          to_upsert = sap.references.find_by(index: i) || StructuredAdvisoryPayloadReference.new(advisory_payload_id: sap.id, index: i)
          to_upsert.url = ref

          indexes_upserted << i
          if dry_run
            logger.call("Dry run would've upserted reference #{ref}")
          else
            to_upsert.save!
          end
        end
      end)

      indexed_upsert_rectifier(dry_run, "vulnerabilities", -> { sap.vulnerabilities }, lambda do |vuln_indexes_upserted|
        ap["vulnerabilities"]&.each do |i, vuln|
          next if vuln["withdrawn"]

          db_vuln = sap.vulnerabilities.find_by(index: i) || StructuredAdvisoryPayloadVulnerability.new(advisory_payload_id: sap.id, index: i)

          db_vuln.package_ecosystem = vuln["ecosystem"]
          db_vuln.package_name = vuln["package_name"]
          db_vuln.vulnerable_version_range = vuln["vulnerable_version_range"]
          db_vuln.first_patched_version = vuln["first_patched_version"]
          vuln_indexes_upserted << i

          if dry_run
            logger.call("Dry run would've upserted vulnerability with index #{i}")
          else
            db_vuln.save!
          end
        end
      end)
    end

    # Weird name, weird job: When we're dealing with upserting a complex object into the DB, we need to make
    # sure we remove rows as part of the upsert. This method does exactly that.
    # This method is sugar to try and keep upsert_structured_payload_for_advisory_payload a little more organized with less repeated boilerplate.
    def self.indexed_upsert_rectifier(dry_run, item_name, get_the_items, indexed_add_the_items)
      indexes_upserted = []
      indexed_add_the_items.call(indexes_upserted)

      clean_these = get_the_items.call.filter { |x| indexes_upserted.exclude?(x.index) }
      if clean_these.present?
        if dry_run
          logger.call("Dry run would've deleted orphaned #{item_name}: #{clean_these.map(&:index)}")
        else
          clean_these.each(&:destroy)
        end
      end
    end
  end
end
