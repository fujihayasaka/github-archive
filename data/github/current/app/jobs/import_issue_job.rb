# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class ImportIssueJob < ApplicationJob
  queue_as :import_issue
  retry_on_dirty_exit

  retry_on Freno::Throttler::CircuitOpen
  retry_on Freno::Throttler::WaitedTooLong

  # Queue an issue import
  def self.enqueue(import_item)
    ImportIssueJob.perform_later("import_item_id" => import_item.id, "repository_id" => import_item.repository_id)
  end

  attr_reader :import_item_id, :repository_id, :options

  # Throttler exceptions raised in lib/github/importer2/issue_creator.rb
  def perform(options)
    @options = options # keep these around in case we need to requeue.
    @import_item_id = options.fetch("import_item_id")
    @repository_id = options.fetch("repository_id")

    Failbot.push("gh.migration_tools.import_item_id" => import_item_id)
    single_file do
      GitHub.dogstats.increment "import_issue.status", tag: ["type:start", "status:#{import_item.status}"]
      with_write { GitHub.issue_importer.create_issue(import_item) }
      GitHub.dogstats.increment "import_issue.status", tag: ["type:finish", "status:#{import_item.status}"]
    end
  end

  # Only allow one of these to run at a time, scoped per repository, but queue up the next one when we're done.
  def single_file
    restraint.lock!(restraint_key, 1, 1.hour) do
      yield
    end
    if next_item = ImportItem.where(repository_id: repository_id, status: "pending").first
      self.class.enqueue(next_item)
    end
  rescue GitHub::Restraint::UnableToLock
    # another job is running, this one will get worked later.
  end

  def import_item
    @import_item ||= ImportItem.find(import_item_id)
  end

  def restraint_key
    "import-issue:repo_#{repository_id}"
  end

  def restraint
    @restraint ||= GitHub::Restraint.new
  end
end
