# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class DeleteOrphanedUser2faRecords < Base
      class TwoFactorCredential < ApplicationRecord::Domain::Users
        self.table_name = :two_factor_credentials
      end

      class TotpAppRegistration < ApplicationRecord::Domain::Users
        self.table_name = :totp_app_registrations
      end

      class SmsRegistration < ApplicationRecord::Domain::Users
        self.table_name = :sms_registrations
      end

      class Users < ApplicationRecord::Domain::Users
        self.table_name = :users
      end

      sig { returns(T.nilable(Integer)) }
      attr_reader :total_orphaned_two_factor_records, :total_orphaned_sms_registrations, :total_orphaned_totp_app_registrations

      iterate_over :database_table, params: {
        model_class: TwoFactorCredential,
        columns: %i[id user_id],
      }

      sig { override.void }
      def after_initialize
        @total_orphaned_two_factor_records = T.let(0, T.nilable(Integer))
        @total_orphaned_sms_registrations = T.let(0, T.nilable(Integer))
        @total_orphaned_totp_app_registrations = T.let(0, T.nilable(Integer))
      end

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        user_ids = items.values.map { |item| item[:user_id] }
        orphaned_two_factor_records = TwoFactorCredential
          .where(user_id: user_ids)
          .joins("LEFT JOIN users ON two_factor_credentials.user_id = users.id")
          .where("users.id IS NULL")

        if orphaned_two_factor_records.empty?
          log "SKIPPING: No orphaned two factor records found"
          return
        end

        orphaned_two_factor_record_ids = orphaned_two_factor_records.pluck(:id)
        orphaned_two_factor_record_user_ids = orphaned_two_factor_records.pluck(:user_id)

        orphaned_totp_records = TotpAppRegistration.where(user_id: orphaned_two_factor_record_user_ids)
        orphaned_sms_records = SmsRegistration.where(user_id: orphaned_two_factor_record_user_ids)

        @total_orphaned_two_factor_records = T.must(@total_orphaned_two_factor_records) + orphaned_two_factor_record_ids.count
        @total_orphaned_totp_app_registrations = T.must(@total_orphaned_totp_app_registrations) + orphaned_totp_records.count
        @total_orphaned_sms_registrations = T.must(@total_orphaned_sms_registrations) + orphaned_sms_records.count

        log "#{dry_run? ? "DRY RUN: Would have deleted" : "Deleted"} #{orphaned_two_factor_record_ids.count} orphaned two factor records"
        log "Affected two_factor credential ids: #{orphaned_two_factor_record_ids.join(', ')}"
        log "Affected user ids: #{orphaned_two_factor_record_user_ids.join(', ')}"
        log "Total Two Factor records #{dry_run? ? "that would be deleted" : "deleted"}: #{@total_orphaned_two_factor_records}"
        log "Total TOTP records #{dry_run? ? "that would be deleted" : "deleted"}: #{@total_orphaned_totp_app_registrations}"
        log "Total SMS records #{dry_run? ? "that would be deleted" : "deleted"}: #{@total_orphaned_sms_registrations}"

        unless dry_run?
          write_to(model_class: TwoFactorCredential) do
            TwoFactorCredential.where(id: orphaned_two_factor_record_ids).destroy_all
          end

          write_to(model_class: TotpAppRegistration) do
            orphaned_totp_records.destroy_all
          end

          write_to(model_class: SmsRegistration) do
            orphaned_sms_records.destroy_all
          end
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
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::DeleteOrphanedUser2faRecords.new(args).run
end
