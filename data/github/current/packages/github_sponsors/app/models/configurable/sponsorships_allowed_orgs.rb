# typed: true
# frozen_string_literal: true

module Configurable
  module SponsorshipsAllowedOrgs
    extend T::Sig
    extend T::Helpers

    requires_ancestor { Business }

    KEY = Configurable::SponsorshipsAccess::KEY

    sig { returns(T::Array[Integer]) }
    def sponsorships_allowed_orgs
      entries = []
      target_ids = self.organization_ids

      target_ids.each_slice(500) do |slice|
        entries.concat ::Configuration::Entry
          .targeting_users
          .named(KEY)
          .with_true_value
          .for_target_id(slice)
          .pluck(:target_id)
      end

      entries
    end
  end
end
