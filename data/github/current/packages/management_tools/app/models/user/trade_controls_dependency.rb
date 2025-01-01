# typed: strict
# frozen_string_literal: true

module User::TradeControlsDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { User }

  included do
    T.bind(self, T.class_of(User))
    has_one :trade_controls_restriction, class_name: "TradeControls::Restriction", autosave: false
  end

  # Public: check if the user has been restricted for trade
  # controls compliance as required by the Office of Foreign
  # Assets Control (OFAC)
  #
  # Returns Boolean
  sig { returns(T::Boolean) }
  def ofac_sanctioned?
    trade_controls_restriction.any?
  end

  # Public: whether this user has partial trade restrictions
  #
  # Returns Boolean
  sig { returns(T::Boolean) }
  def has_partial_trade_restrictions?
    async_trade_controls_restriction.then(&:partial?).sync
  end

  # Public: whether this user has tier_1 trade restrictions
  #
  # Returns Boolean
  sig { returns(T::Boolean) }
  def has_tier_1_trade_restrictions?
    trade_controls_restriction.tier_1?
  end

  # Public: whether this user has tier_0 trade restrictions
  #
  # Returns Boolean
  sig { returns(T::Boolean) }
  def has_tier_0_trade_restrictions?
    trade_controls_restriction.tier_0?
  end

  # Public: whether this user has any tiered restrictions
  #
  # Returns Boolean
  sig { returns(T::Boolean) }
  def has_any_tiered_trade_restrictions?
    has_tier_0_trade_restrictions? || has_tier_1_trade_restrictions?
  end

  # Public: whether this user has full trade restrictions
  #
  # Returns Boolean
  sig { returns(T::Boolean) }
  def has_full_trade_restrictions?
    replica_clusters = T.let([], T::Array[T.class_of(ApplicationRecord::Base)])
    replica_clusters << ApplicationRecord::Collab if GitHub.flipper[:issue_comments_api_use_collab_replica].enabled?
    ActiveRecord::Base.connected_to_many(replica_clusters, role: :reading) do
      async_has_full_trade_restrictions?.sync
    end
  end

  sig { returns(Promise[T::Boolean]) }
  def async_has_full_trade_restrictions?
    async_trade_controls_restriction.then(&:full?)
  end

  # Public: whether this user has tiered trade restrictions
  #
  # Returns Boolean
  sig { returns(T::Boolean) }
  def has_tiered_trade_restrictions?
    trade_controls_restriction.tiered_restriction?
  end

  # Public: whether this user has any trade restrictions
  #
  # Returns Boolean
  sig { returns(T::Boolean) }
  def has_any_trade_restrictions?
    replica_clusters = T.let([], T::Array[T.class_of(ApplicationRecord::Base)])
    replica_clusters << ApplicationRecord::Collab if GitHub.flipper[:issue_comments_api_use_collab_replica].enabled?
    ActiveRecord::Base.connected_to_many(replica_clusters, role: :reading) do
      async_has_any_trade_restrictions?.sync
    end
  end

  # Public: whether this user has any trade restrictions
  #
  # Returns Promise<Boolean>
  sig { returns(Promise[T::Boolean]) }
  def async_has_any_trade_restrictions?
    async_trade_controls_restriction.then(&:any?)
  end

  # Public: returns the has_one :trade_controls_restriction association.
  # If the associated record doesn't exist, it falls back to building a new
  # one. This ensures callers do not need the safe-navigation operator. It
  # also ensures a consistent API between Users with an `unrestricted` record
  # and those without an associated restriction at all; as those two scenarios
  # are semantically the same.
  #
  # Returns TradeControls::Restriction
  sig { returns(TradeControls::Restriction) }
  def trade_controls_restriction
    ActiveRecord::Base.connected_to(role: :reading) { super || build_trade_controls_restriction }
  end

  # Override the built-in async_* association to ensure it is never nil.
  # Whenever the restriction record doesn't exist, we build a new one.
  # see overridden trade_controls_restriction association.
  sig { returns(Promise[TradeControls::Restriction]) }
  def async_trade_controls_restriction
    ActiveRecord::Base.connected_to(role: :reading) do
      super.then do |restriction|
        restriction || trade_controls_restriction
      end
    end
  end

  # Public: Determine if this organization can access a feature based on their restriction tier.
  #
  # object: This is the feature we are checking against a tier for trade restriction. (default: nil)
  #
  # Returns Boolean
  sig { params(type: T.nilable(Symbol)).returns(T::Boolean) }
  def restriction_tier_allows_feature?(type: nil)
    return true unless has_any_trade_restrictions?
    return false if self.is_a?(Organization) && has_full_trade_restrictions?

    case type
    when :repository
      trade_controls_restriction.tier_0?
    else
      false
    end
  end

  sig { returns(T.nilable(OFACDowngrade)) }
  def scheduled_ofac_downgrade
    @ofac_downgrade ||= T.let(OFACDowngrade.incomplete.where(user_id: id).last, T.nilable(OFACDowngrade))
  end

  # Public: Is this user's trade restriction finalized?
  #
  # Returns Boolean
  sig { returns(T::Boolean) }
  def trade_restriction_finalized?
    has_any_trade_restrictions? && complete_ofac_downgrade.present?
  end

  # Public: Is this user's spammy downgrade finalized?
  #
  # Returns Boolean
  sig { returns(T::Boolean) }
  def spammy_downgrade_finalized?
    spammy? && complete_ofac_downgrade.present?
  end

  # Public: Date when the trade restriction downgrade was completed
  #
  # Returns Date or nil
  sig { returns(T.nilable(Date)) }
  def trade_restriction_finalized_date
    complete_ofac_downgrade&.downgrade_on
  end

  # Private: Returns the last completed OFAC downgrade if it exists
  #
  # Returns OFACDowngrade or nil
  sig { returns(T.nilable(OFACDowngrade)) }
  def complete_ofac_downgrade
    @complete_ofac_downgrade ||= T.let(OFACDowngrade.completed.where(user_id: id).last, T.nilable(OFACDowngrade))
  end

  # Internal: Sends an email for the individual actor being restricted
  #
  # Returns nil
  sig { void }
  def send_trade_controls_enforcement_email
    TradeControlsMailer.individual_actor_restricted(T.cast(self, User)).deliver_later
  end

  # Internal: Sends an email for the individual actor being overridden
  #
  # Returns nil
  sig { void }
  def send_trade_controls_override_email
    TradeControlsMailer.individual_actor_reactivated(T.cast(self, User)).deliver_later
  end

  sig { params(compliance: TradeControls::Compliance, kwargs: T.untyped).void }
  def instrument_trade_controls_enforcement(compliance:, **kwargs)
    GlobalInstrumenter.instrument("trade_restriction.flag",
                                  user: self, **compliance.to_hydro, **kwargs)
  end

  sig { params(compliance: TradeControls::Compliance, kwargs: T.untyped).void }
  def instrument_trade_controls_override(compliance:, **kwargs)
    GlobalInstrumenter.instrument("trade_restriction.unflag",
                                  user: self, **compliance.to_hydro, **kwargs)
  end

  sig { void }
  def send_trade_controls_allowed_status_email
    T.bind(self, User)
    TradeScreeningMailer.owner_profile_allowed_status(self).deliver_later
  end

  sig { void }
  def send_trade_controls_not_allowed_status_email
    T.bind(self, User)
    TradeScreeningMailer.owner_profile_not_allowed_status(self).deliver_later
  end

  sig { void }
  def send_trade_controls_data_needs_fixing_status_email
    T.bind(self, User)
    TradeScreeningMailer.owner_profile_data_needs_fixing(self).deliver_later
  end
end
