# typed: strict
# frozen_string_literal: true

module GitHubSponsors
  module Public
    # Public: Get a mapping of which users and organizations are sponsoring a given maintainer.
    #
    # sponsor_or_ids - Array of Users/Orgs or Integer IDs to check for sponsorship
    # sponsorable_id - Integer ID of the User/Org maintainer
    # viewer - the User/Org viewing the results, or nil for an anonymous viewer
    #
    # If no viewer is passed, only public sponsorships will be checked, otherwise
    # the viewer's identity determines which sponsorships will be returned.
    # For example, I can see all private sponsorships I fund, and a maintainer can see
    # my private sponsorship of them but not my other private sponsorships.
    #
    # Returns a Hash of Integer id => Boolean representing whether the viewer
    # can see that the passed User/Org has a sponsorship for the passed maintainer.
    sig do
      params(
        sponsors_or_ids: T::Array[T.any(User, Integer, Organization, String)],
        sponsorable_id: T.any(User, Integer, Organization, String),
        viewer: T.nilable(User)
      ).returns(T::Hash[Integer, T::Boolean])
    end
    def self.sponsor_status_by_sponsor_id(sponsors_or_ids, sponsorable_id:, viewer: nil)
      Sponsorship.sponsor_status_by_sponsor_id(sponsors_or_ids, sponsorable_id: sponsorable_id, viewer: viewer)
    end
  end
end
