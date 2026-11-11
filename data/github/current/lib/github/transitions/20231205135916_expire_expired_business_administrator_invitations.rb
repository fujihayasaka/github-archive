# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

module GitHub
  module Transitions
    class ExpireExpiredBusinessAdministratorInvitations < Base
      # Pending invitations that should have already been expired but haven't been
      iterate_over :database_table, params: {
        model_class: BusinessAdministratorInvitation,
        conditions: "accepted_at IS NULL \
          AND cancelled_at IS NULL \
          AND expired_at IS NULL \
          AND (created_at < '#{GitHub.invitation_expiry_cutoff.days.ago.strftime('%Y-%m-%d %H:%M:%S')}')".squish,
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        items.each do |id, _|
          invitation = ::BusinessAdministratorInvitation.find_by(id: id)
          next if invitation.blank?

          if verbose?
            if dry_run?
              log "Would be expiring BusinessAdministratorInvitation with ID #{invitation.id}"
            else
              log "Expiring BusinessAdministratorInvitation with ID #{invitation.id}"
            end
          end

          unless dry_run?
            write_to(model_class: BusinessAdministratorInvitation) do
              invitation.expire(skip_reinvite: true)
            end
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

  GitHub::Transitions::ExpireExpiredBusinessAdministratorInvitations.new(args).run
end
