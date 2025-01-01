# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Elastomer
  class SearchIndexPrimaryCleanupJob < ApplicationJob
    queue_as :index_high

    retry_on_dirty_exit

    def perform(old_update_aliases_cmds)
      old_update_aliases_cmds.each { |method, args| T.unsafe(SearchIndexManager).send(method, *args) }

      index_name = old_update_aliases_cmds.first.second.second.first.dig(:remove, :index)

      GitHub.dogstats.event \
        "Search index demoted: #{index_name}",
        "Search index #{index_name} was demoted from the primary role.",
      tags: %W[search:ops action:primary]
    end
  end
end
