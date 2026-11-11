# typed: false
# frozen_string_literal: true

class Actions::AllowedTypesUpdater
  include GitHub::Memoizer

  ALL = "all"
  SELECTED = "selected"
  LOCAL_ONLY = "local_only"

  def self.perform(**options)
    new(**options).perform
  end

  def initialize(entity:, policy:, sha_pinning: false, actor:)
    @entity = entity
    @policy = policy
    @old_policy = entity.actions_allowlist
    @actor = actor
    @sha_pinning = sha_pinning
  end

  def perform
    update_settings
    instrument_changes
  end

  private

  def update_settings
    case @policy
    when ALL
      @entity.enable_all_actions(sha_pinning: @sha_pinning)
    when LOCAL_ONLY
      @entity.enable_local_actions_only(sha_pinning: @sha_pinning)
    when SELECTED
      # The only way to represent the "SELECTED" selection is to set
      # `github_owned_allowed` or `verified_allowed` to true. This isn't ideal since
      # users may not actually want this to be predetermined for them. Until we have
      # a system in place to represent ALL vs. LOCAL_ONLY vs. SELECTED, this
      # workaround will do for the time-being.
      @entity.enable_specified_actions_only(github_owned: true, sha_pinning: @sha_pinning, actor: @actor)
    end

    # Handle sha_pinning updates when no policy is provided
    if @policy.nil? && !@sha_pinning.nil?
      if @old_policy.nil? || @old_policy.all_allowed?
        @entity.enable_all_actions(sha_pinning: @sha_pinning)
      else
        # Existing allowlist, just update sha_pinning_required directly
        @old_policy.update(sha_pinning_required: @sha_pinning)
      end
    end
  end

  def instrument_changes
    if @entity.is_a?(Repository)
      Repositories.domain.reload(@entity)
    else
      @entity.reload
    end

    return if @entity.actions_allowlist == @old_policy

    @entity.instrument "update_actions_settings",
      actor:                  @actor,
      new_policy:             @policy,
      updated_allowed_types:  true,
      updated_sha_pinning_required: @sha_pinning
  end

  def enabled_for_selected?
    return @_enabled_for_selected if defined?(@_enabled_for_selected)
    @_enabled_for_selected = @entity.actions_enabled_for_selected_entities?
  end
end
