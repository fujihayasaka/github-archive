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
#   .transitions run <pr-url> <environment> 20240314002209_sort_groups_by_resync.rb -v
#
# To run this transition in write mode, issue the following chatop in the
# #dependabot-ops channel:
#
#   .transitions run <pr-url> <environment> 20240314002209_sort_groups_by_resync.rb -v -w
#
# Once the transition is complete, merge the pull request.
#
module Dependabot
  module Transitions
    class SortGroupsByResync < Dependabot::Transition
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
        # Define the record set you plan to address, ensuring it is retrieved
        # in batches.
        # @iterator = MyModel.scope.in_batches(of: BATCH_SIZE)
        @iterator = Repo.joins(:update_configs).
                    merge(UpdateConfig.active).
                    # exclude records where no dependency_groups exist for an update_config
                    where("EXISTS (SELECT 1 FROM #{::DependencyGroup.table_name} WHERE \
                      #{::DependencyGroup.table_name}.update_config_id = #{::UpdateConfig.table_name}.id)").
                    distinct.in_batches(of: BATCH_SIZE)
      end

      # Returns nothing.
      def perform
        iterator.each_with_index do |rows, index|
          wait = (index * 30).seconds
          process(rows, wait)
        end
      end

      def process(rows, wait)
        rows.each do |repo|
          log "resyncing Repo #{repo.id}" if verbose?
          next if dry_run?

          ::ResyncRepoConfigFileJob.set(wait: wait).perform_later(
            account: repo.account,
            repo_name: repo.name,
            repo_github_id: repo.github_id,
            skip_jobs: true,
            event_source: "sort_groups_transition",
          )
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

  transition = Dependabot::Transitions::SortGroupsByResync.new(**options)
  transition.run
end
