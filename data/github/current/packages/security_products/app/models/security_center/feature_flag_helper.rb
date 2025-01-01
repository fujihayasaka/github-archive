# typed: strict
# frozen_string_literal: true

module SecurityCenter::FeatureFlagHelper

  Actor = T.type_alias { T.any(User, Repository, Organization, Business) }

  sig { params(base: Module).returns(T.noreturn) }
  def self.included(base)
    raise StandardError.new "Don't include this module. Use the fully-qualified name."
  end

  sig { params(base: Module).returns(T.noreturn) }
  def self.extended(base)
    raise StandardError.new "Don't extend this module. Use the fully-qualified name."
  end

  sig { params(base: Module).returns(T.noreturn) }
  def self.prepended(base)
    raise StandardError.new "Don't prepend this module. Use the fully-qualified name."
  end

  # This is not a feature flag
  # For users, we need to make sure they belong to an enterprise managed business.
  # For businesses, they must be enterprise managed.
  sig { params(actor: T.any(User, Business)).returns(T::Boolean) }
  def self.allows_emu_owned_repositories?(actor)
    if actor.is_a?(Business)
      AdvancedSecurity::Features::Business::AdvancedSecurity.new(actor).security_center_for_emus_enabled?
    elsif actor.user?
      AdvancedSecurity::Features::User::AdvancedSecurity.new(actor).security_center_for_emus_enabled?
    else
      false
    end
  end

  sig { params(actors: Actor).returns(T::Boolean) }
  def self.no_visible_features_for_non_emu_owners?(*actors)
    feature_flag :security_center_show_no_visible_features_for_non_emu_owners, actors: actors
  end

  sig { params(actors: Actor).returns(T::Boolean) }
  def self.in_private_beta?(*actors)
    any_actor?(actors) { |actor| actor.feature_enabled?(:security_center_private_beta) }
  end

  sig { params(actors: Actor).returns(T::Boolean) }
  def self.security_center_feedback_link_enabled?(*actors)
    feature_flag :security_center_feedback_link, actors: actors
  end

  sig { params(actors: Actor).returns(T::Boolean) }
  def self.show_code_scanning_linked_alerts?(*actors)
    feature_flag :security_center_show_code_scanning_linked_alerts, actors: actors
  end

  sig { params(actors: T.nilable(Actor)).returns(T::Boolean) }
  def self.use_new_team_dropdown?(*actors)
    feature_flag :security_center_new_team_dropdown, actors: actors.compact
  end

  # Determines whether the given feature is enabled for any of the given actors.
  # Also handles private beta feature enablement.
  #
  # NOTE: Do not rename. This name satisfies the "feature_flags_are_used" lint test without forcing us to duplicate this logic.
  sig { params(feature: Symbol, actors: T::Array[Actor]).returns(T::Boolean) }
  def self.feature_flag(feature, actors:)
    started_at = GitHub::Dogstats.monotonic_time
    tags = { feature: feature }

    feature_private_beta_flag = FlipperFeature.find_by(name: "#{feature}_private_beta")
    feature_enabled_for_private_beta = feature_private_beta_flag&.fully_enabled?

    feature_enabled = any_actor?(actors) do |actor|
      tags[:actor_type] = actor.class.name&.demodulize.underscore

      # the actor is enabled for the feature, either directly or indirectly via group membership
      next true if actor.feature_enabled?(feature)

      # the actor is in the private beta "group", and the feature is enabled for private beta
      # This workaround supports "groups" of arbitrary actors, without requiring
      #   - team membership, which limits to only User actors
      #   - any new models
      next true if feature_enabled_for_private_beta && actor.feature_enabled?(:security_center_private_beta)

      false
    end

    if actors.empty? && !feature_enabled
      feature_flag = GitHub.flipper[feature]
      feature_enabled = feature_flag.enabled? || feature_flag.percentage_of_actors_value == 100
    end

    tags[:result] = feature_enabled

    GitHub.dogstats.distribution(
      "security_center.feature_flag.dist",
      GitHub::Dogstats.duration(started_at),
      tags: tags.map { |k, v| "#{k}:#{v}" }
    )

    feature_enabled
  end

  sig do
    params(
      actors: T::Array[Actor],
      blk: T.proc.params(actor: Actor).returns(T::Boolean) # https://sorbet.org/docs/procs#annotating-methods-that-use-yield
    ).returns(T::Boolean)
  end
  def self.any_actor?(actors, &blk)
    actors.each do |actor|
      if actor.is_a?(Repository)
        return true if yield actor
        actor = actor.owner
      end

      if actor.is_a?(Organization)
        return true if yield actor
        actor = actor.business
      end

      if actor.is_a?(Business)
        return true if yield actor
      end

      if actor.is_a?(User)
        return true if yield actor
      end
    end

    false
  end
end
