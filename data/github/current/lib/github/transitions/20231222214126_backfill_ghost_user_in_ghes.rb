# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillGhostUserInGhes < Base
      iterate_over :database_table, params: {
        model_class: User,
        conditions: "login = '#{GitHub.ghost_user_login}'",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        # We'll always have a gost user, as the query that creates it runs before this transition
        ghost_id = items.keys.first
        ghost = User.unscoped.find_by(id: ghost_id)

        if dry_run?
          log "Dry run. Ghost id id #{ghost_id}"
          return
        end

        # we return if !ghost.present?, so the CI job can pass
        return if !ghost.present? || !ghost.emails.empty?

        # In GHES, the ghost user is created without a password and email and that will raise a validation error while saving
        # the token_secret. Without the token_secret saved, all the signed token validation will fail for the ghost user.
        #
        # References:
        #
        #   Where the ghost user is created:
        #   - https://github.com/github/enterprise2/blob/master/vm_files/usr/local/share/enterprise/ghe-run-migrations#L209
        #
        #   Where the validation error is raised:
        #   - https://github.com/github/github/blob/master/packages/apps/app/models/user/remote_authentication_dependency.rb#L95
        write_to(model_class: User) do
          password = SecureRandom.hex
          ghost.password = password
          ghost.password_confirmation = password
          ghost.email = "ghost@github.com"
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

  GitHub::Transitions::BackfillGhostUserInGhes.new(args).run
end
