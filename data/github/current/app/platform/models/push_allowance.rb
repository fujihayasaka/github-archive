# typed: true
# frozen_string_literal: true

class Platform::Models::PushAllowance
  attr_reader :branch_protection_rule, :actor

  include GitHub::Relay::GlobalIdentification

  def initialize(branch_protection_rule, actor)
    @branch_protection_rule = branch_protection_rule
    @actor = actor
  end

  def self.load_from_global_id(id)
    protected_branch_global_id, actor_global_id = id.split(":", 2)

    protected_branch_id = Platform::Helpers::NodeIdentification.from_global_id(protected_branch_global_id).last
    actor_type, actor_id = Platform::Helpers::NodeIdentification.from_global_id(actor_global_id)

    load_push_allowance(protected_branch_id, actor_type, actor_id)
  end

  def self.load_push_allowance(protected_branch_id, actor_type, actor_id)
    async_protected_branch = Platform::Objects.async_find_record_by_id(ProtectedBranch, protected_branch_id)
    async_protected_branch.then do |protected_branch|
      # If a user is spammy then the actor will be nil
      if actor_type.present?
        async_actor = "Platform::Objects::#{actor_type}".constantize.load_from_global_id(actor_id)
        async_actor.then do |actor|
          new(protected_branch, actor)
        end
      else
        new(protected_branch, nil)
      end
    end
  end

  def global_id
    "#{branch_protection_rule.global_relay_id}:#{actor.global_relay_id}"
  end
end
