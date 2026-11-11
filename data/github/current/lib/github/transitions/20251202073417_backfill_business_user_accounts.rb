# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillBusinessUserAccounts < Base
      iterate_over :database_table, params: {
        model_class: ::User,
        conditions: "type = 'User' AND login <> 'ghost'"
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        return unless GitHub.enterprise?
        business = GitHub.global_business

        users = User.where(id: items.keys).includes(:profile, :emails)
        if dry_run?
          users.each do |user|
            log("[dry_run] would create BUA for user #{user.login} #{user.id}")
          end
          return
        end

        skip_buas = BusinessUserAccount.where(user_id: users.pluck(:id)).pluck(:user_id)
        bua_ids = []
        write_to(model_class: BusinessUserAccount) do
          users.each do |user|
            if skip_buas.include?(user.id)
              log("skipping creating BUA for user #{user.login} #{user.id}, exists already")
              next
            end
            log("creating BUA for user #{user.login} #{user.id}")
            bua = business.user_accounts.create(user: user, business_roles_bitfield: nil)
            if bua&.persisted?
              bua_ids << bua.id
              log("created BUA for user #{user.login} #{user.id} with id #{bua.id}")
            else
              log("failed creating BUA for user #{user.login} #{user.id} - #{bua&.errors}")
            end
          end
        end

        bua_ids.compact!
        if bua_ids.size > 0
          log("updating BUA roles for BUAs #{bua_ids}")
          BusinessUserAccountUpdateAttributesJob.perform_now(business, user_account_ids: bua_ids)
          log("done updating BUA roles for BUAs #{bua_ids}")
        else
          log("skipping updating BUA roles, no BUAs created")
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

  GitHub::Transitions::BackfillBusinessUserAccounts.new(args).run
end
