# typed: strict
# frozen_string_literal: true

module Stores
  class Domain < GH::Domain::Base
    # Given a store ID, get the store
    sig { params(id: String).returns(T.nilable(Store)).checked(:always).on_failure(:raise) }
    def by_id(id)
      reposd_client.get_store(id: id)&.then { |data| Stores::Store.from_reposd(data) }
    end

    private

    # Used to make twirp calls to reposd
    sig { returns(Repositories::ReposdStoresTwirpClient) }
    memoize def reposd_client
      Repositories::ReposdStoresTwirpClient.new
    end
  end
end
