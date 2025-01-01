# typed: strict
# frozen_string_literal: true

class RepairGistsIndexJob < Elastomer::RepairJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :index_bulk

  reconcile "gist",
    fields: %w[updated_at],
    limit: 250,
    accept: :gist_is_searchable?,
    include: [:user]
end
