# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class UserSuspender
      # Public: Makes one big array of logins that should not be suspended and
      # then iterates through each user for the current migration and tests it
      # against the list of logins, suspending the user if it is not included
      # in the list.
      #
      # current_migration - MigratableResource scope.
      def self.process(current_migration)
        logins = T.let([], T::Array[T.untyped])

        current_migration.by_model_type("repository").by_states("imported").find_each do |mr|
          repo    = mr.model
          owner   = repo.owner
          subject = if owner.organization?
            owner
          else
            logins.push(owner.login)
            repo
          end

          logins += subject.members.pluck(:login)
        end

        current_migration.by_states(:imported).by_model_type("user").find_each do |mr|
          user = mr.model

          user.suspend("gh-migrator") unless logins.include?(user.login)
        end
      end
    end
  end
end
