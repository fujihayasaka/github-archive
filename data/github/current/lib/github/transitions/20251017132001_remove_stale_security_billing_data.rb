# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

module GitHub
  module Transitions
    class RemoveStaleSecurityBillingData < Base
      Checker = SecurityProductsEnablement::BillingDataIntegrityChecker

      sig { override.void }
      def after_initialize
        @iterator = Iterators::Csv.new(csv_file: arguments[:csv_file], csv_read_opts: { headers: true })
        @iterator.transition = self
        @iterator.arguments = arguments

        if !remove_stale_advanced_security_configuration_entries? &&
             !remove_stale_code_security_configuration_entries? &&
             !remove_stale_secret_protection_configuration_entries?
          raise ArgumentError, "Must specify at least one argument for which stale configuration entries to remove!"
        end

        @removed_count = T.let(0, T.nilable(Integer))
        @transition_id = T.let(SecureRandom.uuid_v7, T.nilable(String))

        log "Starting transition with ID: #{@transition_id}"

        if verbose?
          tags = ["transition_id:#{@transition_id}", "dry_run:#{dry_run?}"]
          GitHub.dogstats.gauge("remove_stale_security_billing_data.total", @removed_count, tags:)
        end
      end

      sig { override.params(rows: Iterators::Items).void }
      def process_batch(rows)
        log "#{dry_run? ? "Would process" : "Processing"} rows: #{rows.keys.first}-#{rows.keys.last}"

        business_ids = Set.new
        repository_ids = Set.new

        rows.each_value do |row|
          business_id = row[:business_id]&.to_i
          business_ids.add(business_id) if business_id

          repository_id = row[:repository_id]&.to_i
          repository_ids.add(repository_id) if repository_id
        end

        business_ids = business_ids.to_a
        repository_ids = repository_ids.to_a.presence # Cast to nil if empty

        if repository_ids
          log "#{dry_run? ? "Would process" : "Processing"} repository IDs: #{repository_ids.inspect}"
        else
          log "#{dry_run? ? "Would process" : "Processing"} business IDs: #{business_ids.inspect}"
        end

        problem_repository_ids = []
        advanced_security_problem_repository_ids = []
        code_security_problem_repository_ids = []
        secret_protection_problem_repository_ids = []

        Checker.check(business_ids:, repository_ids:) do |problem, problem_repositories|
          batch_of_problem_repository_ids = problem_repositories.map(&:id)
          problem_repository_ids.concat(batch_of_problem_repository_ids)

          case problem
          when Checker::Problem::AdvancedSecurity
            advanced_security_problem_repository_ids.concat(batch_of_problem_repository_ids)
          when Checker::Problem::CodeSecurity
            code_security_problem_repository_ids.concat(batch_of_problem_repository_ids)
          when Checker::Problem::SecretProtection
            secret_protection_problem_repository_ids.concat(batch_of_problem_repository_ids)
          else
            T.absurd(problem)
          end
        end

        remove_stale_configuration_entries(
          name: Checker::REPOSITORY_ADVANCED_SECURITY_KEY,
          repository_ids: advanced_security_problem_repository_ids,
        ) if remove_stale_advanced_security_configuration_entries?

        remove_stale_configuration_entries(
          name: Checker::REPOSITORY_CODE_SECURITY_KEY,
          repository_ids: code_security_problem_repository_ids,
        ) if remove_stale_code_security_configuration_entries?

        remove_stale_configuration_entries(
          name: Checker::REPOSITORY_SECRET_PROTECTION_KEY,
          repository_ids: secret_protection_problem_repository_ids,
        ) if remove_stale_secret_protection_configuration_entries?

        log "#{dry_run? ? "Would have removed" : "Removed"} #{@removed_count} total stale configuration entries"

        if verbose?
          tags = ["transition_id:#{@transition_id}", "dry_run:#{dry_run?}"]
          GitHub.dogstats.increment("remove_stale_security_billing_data.batch", tags:)
          GitHub.dogstats.increment("remove_stale_security_billing_data.processed", by: problem_repository_ids.count, tags:)
          GitHub.dogstats.gauge("remove_stale_security_billing_data.total", @removed_count, tags:)
        end
      end

      private

      sig { returns(T::Boolean) }
      def remove_stale_advanced_security_configuration_entries?
        arguments[:advanced_security].present?
      end

      sig { returns(T::Boolean) }
      def remove_stale_code_security_configuration_entries?
        arguments[:code_security].present?
      end

      sig { returns(T::Boolean) }
      def remove_stale_secret_protection_configuration_entries?
        arguments[:secret_protection].present?
      end

      sig { params(name: String, repository_ids: T::Array[Integer]).void }
      def remove_stale_configuration_entries(name:, repository_ids:)
        if repository_ids.empty?
          log "No stale configuration entries named #{name.inspect} to remove"
          return
        end

        log "#{dry_run? ? "Would remove" : "Removing"} stale configuration entries named #{name.inspect} for repository IDs: #{repository_ids.inspect}"

        removed_repository_ids = []

        # Batching here isn't necessary because the process_batch method is
        # already right-sized.
        #
        # We destroy records (rather than deleting them) so instrumentation
        # is still triggered, causing audit log entries to be created.
        Configuration::Entry
          .named(name)
          .targeting_repository_ids(repository_ids)
          .each do |configuration_entry|
            removed_repository_ids << configuration_entry.target_id

            next if dry_run?

            write_to(model_class: Configuration::Entry) do
              configuration_entry.destroyer = User.staff_user
              configuration_entry.destroy!
            end
          end

        @removed_count = T.must(@removed_count) + removed_repository_ids.count
        log "#{dry_run? ? "Would have removed" : "Removed"} stale configuration entries named #{name.inspect} for repository IDs: #{removed_repository_ids.inspect}"

        if verbose?
          tags = ["transition_id:#{@transition_id}", "configuration_entry_name:#{name}", "dry_run:#{dry_run?}"]
          GitHub.dogstats.increment("remove_stale_security_billing_data.targeted", by: repository_ids.count, tags:)
          GitHub.dogstats.increment("remove_stale_security_billing_data.removed", by: removed_repository_ids.count, tags:)
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV, additional_arguments: [
    "csv_file",           # Path to the CSV (or gzipped CSV) file
    "advanced_security",  # Whether to remove stale Advanced Security configuration entries
    "code_security",      # Whether to remove stale Code Security configuration entries
    "secret_protection",  # Whether to remove stale Secret Protection configuration entries
  ])

  GitHub::Transitions::RemoveStaleSecurityBillingData.new(args).run
end
