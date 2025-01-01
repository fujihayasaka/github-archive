# typed: strict
# frozen_string_literal: true

class RepairGistsIndexJob < Elastomer::RepairJob
  queue_as :index_bulk

  reconcile "gist",
    fields: %w[updated_at],
    limit: 250,
    accept: :gist_is_searchable?,
    include: [:user]
end
