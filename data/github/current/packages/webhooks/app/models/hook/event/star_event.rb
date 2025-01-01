# typed: true
# frozen_string_literal: true

class Hook::Event::StarEvent < Hook::Event

  supports_targets *DEFAULT_TARGETS
  event_attr :user_id, :starred_id, :action, required: true
  event_attr :star_id

  description "A star is created or deleted from a repository."

  def actor
    @actor ||= User.find(user_id)
  end

  def star
    @star ||= if actor&.feature_flag_enabled_or_raise?(:stars_domain_stars_by_ids) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      Stars.domain.by_id(T.must(star_id))
    else
      Star.find_by(id: star_id)
    end
  end

  def target_repository
    @target_repository ||= Repositories.domain.by_id(starred_id)
  end
end
