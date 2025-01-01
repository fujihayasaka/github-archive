# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class BlockAccountsActionInvocation < Platform::Mutations::Base
      description "Block action invocation for accounts."

      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      argument :account_ids, [ID], "The global relay IDs of the accounts to block action invocation for.", required: true

      field :accounts, [Platform::Unions::Account], "The accounts for which action invocation was blocked.", null: true

      def resolve(**inputs)
        unless self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have permission to block action invocation."
        end

        account_promises = inputs[:account_ids].map do |gid|
          Platform::Helpers::NodeIdentification.async_typed_object_from_id \
            Platform::Unions::Account.possible_types, gid, context
        end

        Promise.all(account_promises).then do |accounts|
          accounts.each do |account|
            Actions::Invocation.block(actor: account, staff_actor: context[:viewer])
          end

          { accounts: accounts }
        end.sync
      end
    end
  end
end
