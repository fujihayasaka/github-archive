# typed: strict
# frozen_string_literal: true

module Repositories
  class Domain
    class RefUpdates < GH::Domain::Base
      include GitHub::ResilienceMixin

      # Fetches ref updates for given repository and pusher newer than specified pushed_at date.
      #
      # Serves data for `recently_touched_branches_for` method,
      # that gets the repository's three branches whose heads were most recently touched by the specified user.
      # pushed_at param is always set to 1.hour.ago
      sig { params(repository_id: Integer, pusher_id: Integer, pushed_at: Time).returns(GH::Domain::Collection[Repositories::RefUpdate]).checked(:always).on_failure(:raise) }
      def latest_for(repository_id:, pusher_id:, pushed_at:)
        results = ::RefUpdate.joins("INNER JOIN pushes ON pushes.id = ref_updates.push_id AND pushes.repository_id = ref_updates.repository_id")
          .where(pushes: { repository_id: repository_id, pusher_id: pusher_id, pushed_at: pushed_at.. })
          .order(pushed_at: :desc)
          .to_a
        GH::Domain::Collection.new(RefUpdate.from_records(results))
      end
    end
  end
end
