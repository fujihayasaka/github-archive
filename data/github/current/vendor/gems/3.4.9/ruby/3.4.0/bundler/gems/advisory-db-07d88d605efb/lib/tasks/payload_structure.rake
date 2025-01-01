# frozen_string_literal: true

require "hashdiff"

PAYLOAD_STRUCTURING_BATCH_SIZE = 100

# raised when a payload comparison results in mismatched contents
class PayloadComparisonError < StandardError; end

namespace :payload_structure do
  desc "Reset existing structured payload tables to their original state."
  task :reset_structured_payload_tables, [:dry_run, :verbose] => :environment do |_, args|
    dry_run = args[:dry_run] != "false"
    verbose = args[:verbose] != "false"

    total_count = 0

    ActiveRecord::Base.logger.level = :error

    puts "---- DRY RUN ----" if dry_run

    StructuredAdvisoryPayload.find_in_batches(batch_size: PAYLOAD_STRUCTURING_BATCH_SIZE) do |batch|
      puts "Structured Advisory Payload ID BATCH STARTING - #{batch.first.id}"
      total_count += batch.count

      batch.each do |payload|
        puts "ID - #{payload.id}" if verbose
        puts "Review ID - #{payload.payload_container.id}" if verbose
        puts "GHSA - #{payload.payload_container.ghsa_id}" if verbose

        begin
          payload.destroy unless dry_run
        rescue StandardError => error
          puts "ERROR - encountered exception in payload container #{error.message}"
          puts error.backtrace

          raise error unless dry_run

          next
        end

        print "---------------------------\n" if verbose
      end
    end

    puts "---- DRY RUN ----" if dry_run
    puts "Deleted #{total_count} structured advisory payloads"
  end

  desc "Take existing advisory payloads and convert them to structured payloads."
  task :backfill_structured_payload, [:dry_run, :verbose] => :environment do |_, args|
    dry_run = args[:dry_run] != "false"
    verbose = args[:verbose] != "false"

    total_count = 0

    ActiveRecord::Base.logger.level = :error

    puts "---- DRY RUN ----" if dry_run

    AdvisoryReview.find_in_batches(batch_size: PAYLOAD_STRUCTURING_BATCH_SIZE) do |batch|
      puts "ADVISORY REVIEW ID BATCH STARTING - #{batch.first.id}"
      total_count += batch.count

      batch.each do |review|
        puts "ID - #{review.id}" if verbose
        puts "GHSA - #{review.ghsa_id}" if verbose
        puts "OLD - #{review.advisory_payload}" if verbose

        begin
          logger = ->(msg) { puts msg }
          AdvisoryDB::AdvisoryPayloadConverter.upsert_structured_payload_for_advisory_payload(review, dry_run:, logger:)
        rescue StandardError => error
          puts "ERROR - encountered exception in advisory review #{review.ghsa_id}: #{error.message}"
          puts review.advisory_payload
          puts error.backtrace

          raise error unless dry_run

          next
        end

        print "---------------------------\n" if verbose
      end
    end

    puts "---- DRY RUN ----" if dry_run
    puts "Transitioned #{total_count} advisory reviews"
  end

  desc "Compare structured payloads to their raw payload, logging errors if mismatch occurs."
  task :verify_structured_payload, [:console_only_errors] => :environment do |_, args|
    console_only_errors = args[:console_only_errors] != "false"

    total_count = 0
    error_count = 0
    ActiveRecord::Base.logger.level = :error

    AdvisoryReview.find_in_batches(batch_size: PAYLOAD_STRUCTURING_BATCH_SIZE) do |batch|
      puts "ADVISORY REVIEW ID BATCH STARTING - #{batch.first.id}"
      batch.each do |review|
        puts "ID - #{review.id}"
        puts "GHSA - #{review.ghsa_id}"

        begin
          total_count += 1
          compare_structured_payload(review)
          print "---------------------------\n" if verbose
        rescue StandardError => error
          error_count += 1
          if console_only_errors
            print error.full_message
          else
            Failbot.report!(error)
            GitHub::Telemetry::Logs.logger.error("Error while validating advisory reviews match", exception: error)
          end
          print "---------------------------\n" if verbose
          next
        end
      end
    end

    puts "Compared #{total_count} advisory reviews"
    puts "#{error_count} set(s) of advisory payloads didn't match"
  end

  def compare_structured_payload(advisory_review)
    unstructured_hash = AdvisoryPayload.new(data: advisory_review.advisory_payload).hydro_payload
    structured_hash = advisory_review.structured_advisory_payload&.comparison_hash

    if structured_hash.blank?
      raise PayloadComparisonError, "Payload comparison failed for advisory review id #{advisory_review.id} ghsa_id #{advisory_review.ghsa_id}. \n No structured payload was found."
    end

    # drop top level WITHDRAWN property -- it's not used for advisory review structured data.
    unstructured_hash.delete(:withdrawn)

    unstructured_hash[:vulnerabilities].each { |v| normalize_package_ecosystem_case(v) }
    structured_hash[:vulnerabilities].each { |v| normalize_package_ecosystem_case(v) }

    unstructured_hash[:severity] = unstructured_hash[:severity]&.downcase
    structured_hash[:severity] = structured_hash[:severity]&.downcase

    normalize_vulnerability_withdrawn_fields(unstructured_hash[:vulnerabilities], structured_hash[:vulnerabilities])

    diff = Hashdiff.diff(unstructured_hash, structured_hash)

    if diff.count > 0
      raise PayloadComparisonError, "Payload comparison failed for advisory review id #{advisory_review.id} ghsa_id #{advisory_review.ghsa_id}. \n Diff contents were #{JSON.pretty_generate(diff)}"
    end
  end

  def normalize_package_ecosystem_case(vulnerability)
    vulnerability[:package_ecosystem] = vulnerability[:package_ecosystem].downcase
  end

  def normalize_vulnerability_withdrawn_fields(unstructured_vulnerabilities, structured_vulnerabilities)
    unstructured_vulnerabilities.each_with_index do |u_v, i|
      s_v = structured_vulnerabilities[i]
      if !u_v[:withdrawn].presence && s_v[:withdrawn] == false
        s_v.delete(:withdrawn)
      end
    end
  end
end
