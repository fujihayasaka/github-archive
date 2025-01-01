# typed: true
# frozen_string_literal: true

module ProgrammaticAccessGrant
  class Service
    include ActiveModel::Model

    attr_accessor :grant, :actor, :target, :grant_ids, :grants, :skip_revoke_notification

    validates_presence_of :actor, message: "must exist", on: [:revoke, :bulk_revoke]
    validates_presence_of :target, message: "must exist", on: [:bulk_revoke]
    validates_presence_of :grant_ids, message: "must exist", on: [:bulk_revoke]

    validate :actor_can_revoke_grant, on: [:revoke]
    validate :actor_can_revoke_grants, on: [:bulk_revoke]

    validates_length_of :grant_ids, minimum: 1, message: "must not be empty", on: [:bulk_revoke]

    validate :all_grants_belong_to_target, if: -> do
      @target.present? && @grant_ids.present?
    end, on: [:bulk_revoke]

    def self.revoke(grant, actor, skip_revoke_notification: false)
      attributes = {
        grant: grant,
         actor: actor,
         skip_revoke_notification: skip_revoke_notification
      }
      new(attributes).revoke
    end

    # Revokes a grant by destroying it.
    #
    # Returns an (Organization|User)ProgrammaticAccessGrant
    def revoke
      if self.invalid?(:revoke)
        @grant.errors.merge!(self.errors)
        return @grant
      end

      if @grant.destroy
        access = @grant.user_programmatic_access
        target = @grant.target
        UserProgrammaticAccess.notify_owner(about: :revoked, accesses: [access], owner: access.owner, target: target) unless skip_revoke_notification
      end

      @grant
    end

    def self.bulk_revoke(grant_ids, actor, target)
      attributes = {
        grant_ids: grant_ids,
        actor: actor,
        target: target
      }

      new(attributes).bulk_revoke
    end

    # Revokes given grant_ids by destroying their records.
    #
    # Returns self
    def bulk_revoke
      @grants = fetch_grants

      if self.invalid?(:bulk_revoke)
        return self
      end

      # We're passing actor.ability_delegate to retain authn context actor.
      BulkRevokeProgrammaticAccessGrantsJob.perform_later(grant_ids: grant_ids, actor: actor.ability_delegate, target: target)

      self
    end

    private

    def actor_can_revoke_grant
      return true if @grant.writable_by?(@actor)

      self.errors.add(:actor, message: "must have sufficient permissions to revoke this grant")
    end

    def actor_can_revoke_grants
      return true if @grants.all? { |grant| grant.writable_by?(@actor) }

      self.errors.add(:actor, message: "must have sufficient permissions to revoke grants")
    end

    def fetch_grants
      return [] if @grant_ids.nil? || @target.nil?

      ProgrammaticAccessGrant.
        with_target(@target).
        where(id: @grant_ids).
        preload(user_programmatic_access: [:owner])
    end

    def all_grants_belong_to_target
      return true if @grants.count == @grant_ids.uniq.count

      self.errors.add(:grants, message: "one or more grants do not belong to the target.")
    end
  end
end
