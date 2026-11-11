# typed: true
# frozen_string_literal: true

module Configurable
  module MarketplaceCreatorVerification
    extend T::Helpers

    requires_ancestor { Organization }

    KEY = "marketplace_creator_verification".freeze
    DEFAULT = 0 # not applied yet and can apply
    APPLIED = 1 # already applied and can not apply again unless approved or rejected.
    APPROVED = 2 # application is approved and can not apply again
    REJECTED = 3 # application is rejected, can apply again

    # Updates the state of user Request. this will be used to also verify
    def creator_verification_state_update(actor = nil, state)
      config.set!(KEY, state, actor)
      instrument_verification_state_change(actor, state)
      Marketplace::Listing.for_org(id).each(&:synchronize_search_index)
      RepositoryStack.owned_by(id).each(&:synchronize_search_index)
    end

    # Gets the current state of an org, for marketplace verification
    # Marketplace::CreatorVerificationState - Applied , Rejected, Approved
    # if the request is approved. another variable is set which is just to say that Org is verified.
    # if request approved we also reset the state back to NONE.
    # same config can be used to also scan in the biztool to find the orgs which have applied
    # actor - user doing the action
    def creator_verification_state?
      value = config.get(KEY) || DEFAULT
      value.to_i
    end

    # Gets a relation of the organizations that have applied for marketplace verified creator
    #
    # Returns: ActiveRecord::Relation<Organization>
    def self.pending_verification_request(state, name = nil)

      query = Organization.order("created_at ASC")
      if state == DEFAULT
        if name != nil
          query.where("login Like ?", "%#{name}%")
        else
          query
        end
      else
        org_ids = Configuration::Entry.named(KEY).with_value(state).targeting_users.pluck(:target_id)
        query = query.where(id: org_ids)
        if name != nil
          query.where("login Like ?", "%#{name}%")
        else
          query
        end
      end
    end

    def instrument_verification_state_change(actor, state)
      # Hydro
      GlobalInstrumenter.instrument("marketplace.creator_verification_state_update", {
        owner: self,
        actor: actor,
        state: state
      })
    end
  end
end
