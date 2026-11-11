# typed: true
# frozen_string_literal: true

class Stafftools::SpammyRenameDeleteOverride
  include Instrumentation::Model

  ACCEPTED_TYPES = [:renaming, :deleting]

  # Public: toggles the ability for a spammy user to rename or delete themselves
  #
  # actor - staff member who initiates the actions
  # user - the spammy user
  # toggle_type - one of the accepted actions allowed in this class
  #
  # Returns nothing
  def self.toggle_override(actor:, user:, toggle_type:)
    return false if !toggle_type_valid?(toggle_type)

    instance = new(actor: actor, user: user, toggle_type: toggle_type)

    if instance.overridden?
      instance.delete_override!
    else
      instance.enable_override!
    end
  end

  # Public: runs a background job to find all the user's spammy orgs and sets override
  #
  # actor - staff member who initiates the action
  # user - the spammy user
  # toggle_type - one of the accepted actions allowed in this class
  #
  # Returns nothing
  def self.toggle_override_for_owned_orgs(actor:, user:, toggle_type:)
    return false if !toggle_type_valid?(toggle_type)

    toggle_state = orgs_overridden?(user: user, toggle_type: toggle_type) ? :disabled : :enabled
    OverrideSpammyRenamingDeletingAbilitiesJob.perform_later(actor.id, user.id, toggle_type, toggle_state)
  end

  # Public: Does an override exist for this user for this toggle_type?
  #
  # user - User model instance.
  # toggle_type - Symbole representing the type of toggle.
  #
  # Returns a Boolean.
  def self.overridden?(user:, toggle_type:)
    new(user: user, toggle_type: toggle_type).overridden?
  end

  # Public: Does an override exist for this user's orgs for this override type?
  #
  # user - User model instance.
  # toggle_type - Symbole representing the type of toggle.
  #
  # Returns a Boolean.
  def self.orgs_overridden?(user:, toggle_type:)
    new(user: user, toggle_type: toggle_type).orgs_overridden?
  end

  attr_reader :user, :toggle_type

  def initialize(actor: nil, user:, toggle_type:)
    @actor = actor
    @user = user
    @toggle_type = toggle_type
  end

  # Internal: The kv key used to check if override exists
  def kv_key
    @kv_key ||= "user_id.#{@user.id}.#{@toggle_type}_overridden"
  end

  def kv_org_key
    @kv_org_key ||= "user_id.#{@user.id}.#{@toggle_type}_spammy_orgs_overridden"
  end

  # Internal: Checks to see if the toggle_type is one of the accepted types
  def self.toggle_type_valid?(toggle_type)
    ACCEPTED_TYPES.include?(toggle_type)
  end

  # Internal: sets the override and creates audit log
  def enable_override!
    Spam::Kv.store.set(kv_key, Time.zone.now.to_s)
    instrument_update(user, toggle_type, "enable override")
  end

  # Internal: deletes the override and creates audit log
  def delete_override!
    Spam::Kv.store.del(kv_key)
    instrument_update(user, toggle_type, "delete override")
  end

  # Internal: checks to see if the override exists
  def overridden?
    Spam::Kv.store.exists(kv_key).value!
  end

  # Internal: checks to see if all orgs were overridden
  def orgs_overridden?
    Spam::Kv.store.exists(kv_org_key).value!
  end

  # Internal: enables the org override and creates audit log
  def enable_org_override!
    Spam::Kv.store.set(kv_org_key, Time.zone.now.to_s)
    instrument_update(user, toggle_type, "enable override")
  end

  # Internal: deletes the org override and creates audit log
  def delete_org_override!
    Spam::Kv.store.del(kv_org_key)
    instrument_update(user, toggle_type, "delete override")
  end

  # Internal: audit log prefix
  def event_prefix
    "stafftools_spammy_override"
  end

  def instrument_update(user, toggle_type, override_type)
    payload = {
      user: user,
      user_id: user.id,
      toggle_type: toggle_type,
      override_type: override_type,
    }

    instrument :update, payload
  end
end
