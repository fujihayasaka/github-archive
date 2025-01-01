# typed: strict
# frozen_string_literal: true

class GistSynchronizeSearchIndexJob < ApplicationJob
  extend T::Sig

  queue_as :gist_synchronize_search_index

  retry_on_dirty_exit

  sig { params(gist_id: Integer).void }
  def perform(gist_id)
    gist = Gist.find_by(id: gist_id)

    if gist&.gist_is_searchable?
      Search.add_to_search_index("gist", gist_id)
    else
      RemoveFromSearchIndexJob.perform_later("gist", gist_id)
    end
  end
end
