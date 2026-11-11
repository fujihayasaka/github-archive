# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ClearLegalHold < Platform::Mutations::Base
      description "Clear legal holds from a set of accounts."

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :account_ids, [ID], "The global relay ids of accounts to clear legal holds from.", required: true, loads: Platform::Unions::Account
      argument :staff_note, String, "Adds a staff note to the account owner", required: false

      field :accounts, [Unions::Account], "The accounts that had legal holds cleared.", null: true

      def resolve(accounts:, **inputs)
        unless self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have permission to clear legal holds."
        end

        staff_note = inputs[:staff_note]

        accounts.each do |account|
          # Skip accounts that don't support legal holds (e.g., Enterprise accounts)
          next unless account.respond_to?(:legal_hold?) && account.respond_to?(:clear_legal_hold)

          # Skip if no legal hold exists
          next unless account.legal_hold?

          if account.clear_legal_hold(actor: context[:viewer])
            if staff_note.present? && !GitHub.enterprise?
              StaffNote.create(
                user: context[:viewer],
                notable: account,
                note: staff_note,
              )
            end
          end
        end

        { accounts: accounts }
      end
    end
  end
end
