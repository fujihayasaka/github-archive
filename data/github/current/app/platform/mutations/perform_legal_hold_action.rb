# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class PerformLegalHoldAction < Platform::Mutations::Base
      description "Perform legal hold actions on accounts (place or clear legal holds)"

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :account_ids, [ID], "The global relay ids of accounts to perform legal hold action on.", required: true, loads: Objects::User, as: :accounts
      argument :action, Enums::LegalHoldAction, "The legal hold action to perform.", required: true
      argument :staff_note, String, "Adds a staff note to the account owner", required: false

      field :successes, [Objects::User], "The accounts that successfully had the legal hold action performed.", null: true
      field :failures, [Objects::User], "The accounts that failed to have the legal hold action performed.", null: true
      field :errors, [String], "The errors that caused failures.", null: true

      def resolve(accounts:, action:, **inputs)
        unless self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have permission to perform legal hold actions."
        end

        valid_actions = Enums::LegalHoldAction.graphql_values
        unless valid_actions.include?(action)
          raise Errors::Validation.new("Invalid action: #{action}. Must be one of: #{valid_actions.join(', ')}.")
        end

        staff_note = inputs[:staff_note]
        successes = []
        failures = []
        errors = []

        accounts.each do |account|
          result = case action
          when "PLACE"
            handle_place_action(account, staff_note)
          when "CLEAR"
            handle_clear_action(account, staff_note)
          else
            { success: false, error: "Invalid action: #{action}" }
          end

          if result[:success]
            successes << account
            if staff_note.present? && !GitHub.enterprise?
              StaffNote.create(
                user: context[:viewer],
                notable: account,
                note: staff_note,
              )
            end
          else
            failures << account
            errors << result[:error]
          end
        end

        { successes: successes, failures: failures, errors: errors }
      end

      private

      def handle_place_action(account, staff_note)
        # Skip if already has legal hold
        if account.legal_hold?
          return { success: false, error: "#{account.display_login} already has a legal hold" }
        end

        if account.place_legal_hold(actor: context[:viewer])
          { success: true }
        else
          { success: false, error: "Failed to place legal hold on #{account.display_login}" }
        end
      end

      def handle_clear_action(account, staff_note)
        # Skip if no legal hold exists
        unless account.legal_hold?
          return { success: false, error: "#{account.display_login} does not have a legal hold to clear" }
        end

        if account.clear_legal_hold(actor: context[:viewer])
          { success: true }
        else
          { success: false, error: "Failed to clear legal hold on #{account.display_login}" }
        end
      end
    end
  end
end
