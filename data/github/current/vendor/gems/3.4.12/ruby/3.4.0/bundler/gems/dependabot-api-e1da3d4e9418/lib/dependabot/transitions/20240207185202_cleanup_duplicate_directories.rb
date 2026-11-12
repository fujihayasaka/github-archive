# frozen_string_literal: true

require_relative "../../../config/environment"
require "slop"
require "dependabot/transition"

#
# Transitions are orchestrated by the GitHub transitions service and are run
# via chatops:
#
#   .transitions run <pr-url> <environment> <arguments>
#
# A pull request is required to run a transition, so the first step is to
# create one for the transition files.
#
# To run a transition in a particular stamp, specify the stamp as the
# <environment>, e.g., prod-weu-01. To run a transition in all stamps,
# specify * as the <environment>.
#
# Before running a transition you should lock dependabot-api deployments.
#
# To run this transition in dry-run mode, issue the following chatop in the
# #dependabot-ops channel:
#
#   .transitions run <pr-url> <environment> 20240207185202_cleanup_duplicate_directories.rb -v
#
# To run this transition in write mode, issue the following chatop in the
# #dependabot-ops channel:
#
#   .transitions run <pr-url> <environment> 20240207185202_cleanup_duplicate_directories.rb -v -w
#
# Once the transition is complete, merge the pull request.
#
module Dependabot
  module Transitions
    class CleanupDuplicateDirectories < Dependabot::Transition
      # Transitions provide an alternative to running arbitrary code in
      # production without code review.
      #
      # When designing a transition, favor an approach that can be run in small
      # batches and ensure your script is idempotent and safe to resume/re-run.
      #
      # Database connections default to writing, so be sure to test dry runs
      # thoroughly.

      # Recommended batch size number, but you can modify for your use case
      BATCH_SIZE = 100

      attr_reader :iterator

      def after_initialize
        # Should return 111 results
        update_configs = UpdateConfig.
                         active.
                         where(directory: nil).
                         select(:repo_id, :package_manager).
                         group(:repo_id, :package_manager).
                         having("count(*) > 1")

        # Define the record set you plan to address, ensuring it is retrieved
        # in batches.
        # @iterator = MyModel.scope.in_batches(of: BATCH_SIZE)
        @iterator = Repo.where(id: update_configs.map(&:repo_id)).find_in_batches(batch_size: BATCH_SIZE)
      end

      # Returns nothing.
      def perform
        iterator.each do |rows|
          process(rows)
        end
      end

      def process(rows)
        rows.each do |repo|
          # find all grouped security update configs
          update_configs_by_package_manager = UpdateConfig.active.where(repo: repo,
                                                                        directory: nil).group_by(&:package_manager)

          update_configs_by_package_manager.each_value do |update_configs|
            next unless update_configs.count > 1

            # delete all but one
            update_configs.drop(1).each do |uc|
              log("Deleting duplicate update config: #{uc.id} in nwo: #{repo.github_id}")
              uc.transition_to!(:deleted) unless dry_run?
            end
          end
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $PROGRAM_NAME == __FILE__
  slop = Slop.parse(help: true, strict: true) do |options|
    options.bool "-w",
                 "--write",
                 "Enable writes - this defaults to false for safety.",
                 default: false

    options.bool "-v",
                 "--verbose",
                 "Log verbose output"
  end

  options = slop.to_hash
  options = options.merge(dry_run: !options[:write])

  transition = Dependabot::Transitions::CleanupDuplicateDirectories.new(**options)
  transition.run
end
