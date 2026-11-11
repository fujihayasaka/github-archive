# typed: true
# frozen_string_literal: true

class Hook::Event::DeployKeyEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS
  event_attr :repository_id, :key_id, :action, required: true
  event_attr :actor_id, :async_event_context

  description "A deploy key is created or deleted from a repository."

  def actor
    @actor ||= User.find_by(id: actor_id) || User.ghost
  end

  def key
    @key ||= if !async_event_context.blank?
      build_deleted_key_snapshot
    else
      PublicKey.find_by(id: key_id)
    end
  end

  def target_repository
    @target_repository ||= Repositories.domain.by_id(repository_id)
  end

  def deliverable?
    key.present? && actor.present? && target_repository.present?
  end

  private

  def build_deleted_key_snapshot
    # Builds an object out of the given hash of attributes
    attrs = async_event_context.to_h.symbolize_keys

    DeletedKeySnapshot.new(
      id: attrs[:public_key_id] || key_id,
      key: attrs[:key],
      title: attrs[:title],
      created_at: attrs[:created_at],
      accessed_at: attrs[:accessed_at],
      verified: attrs[:verified],
      read_only: attrs[:read_only]
    )
  end

  class DeletedKeySnapshot
    attr_reader :id, :title, :key, :created_at, :accessed_at, :read_only, :verified

    def initialize(id:, title:, key:, created_at:, accessed_at:, read_only:, verified:)
      @id = id
      @title = title
      @key = key
      @created_at = created_at
      @accessed_at = accessed_at
      @read_only = read_only
      @verified = verified
    end

    def read_only?
      @read_only == "true"
    end

    def verified?
      @verified == "true"
    end

    def repository
      nil
    end

    def repository_key?
      false
    end

    def oauth_authorization
      nil
    end

    def creator
      nil
    end
  end
end
