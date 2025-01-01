# typed: true
# frozen_string_literal: true

module Repository::ArchivedDependency
  extend T::Helpers

  requires_ancestor { Repository }

  def self.included(base)
    base.scope :archived_scope,     -> { T.unsafe(self).where(maintained: false) }
    base.scope :not_archived_scope, -> { T.unsafe(self).where(maintained: true) }

    # Public: Query if a repository is archived (read-only).
    #
    # The Repository#archived? method is preloadable for large collections of
    # repositories using GitHub::PrefillAssociations.prefill_batch_method.
    base.batch_method(:archived?, T::Boolean) do |repositories|
      archived_values = Promise.all(repositories.map(&:async_archived?)).sync
      repositories.each_with_index.to_h { |r, i| [r, archived_values.fetch(i)] }
    end
  end

  def async_archived?
    return Promise.resolve(@archived) if defined?(@archived)
    return Promise.resolve(@archived = true) if !maintained?

    async_trade_compliance_read_only?.then do |read_only|
      @archived = read_only
    end
  end

  # Public: Mark a repository as archived so it is read-only.
  def set_archived(synchronous: false)
    return true if !maintained?

    begin
      orchestration = RepositoryOrchestration.archive(T.cast(self, Repository), actor: actor) # rubocop:todo GitHub/AvoidCast

      if orchestration.valid?
        orchestration.execute(synchronous:)
        return true
      end

      GitHub.logger.info(
        "Archive Repository Failed",
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.request_id" => GitHub.context[:request_id],
        "gh.repo.orchestration.id" => orchestration.id,
        "gh.repo.orchestration.state" => orchestration.state,
        "gh.repo.orchestration.repository.errors" => orchestration.errors&.where(:repository)&.map { |e| e.message }&.join(", "),
        "gh.repo.id" => self.id
      )

      false
    ensure
      reset_archived
    end
  end

  # Public: Mark a repository no longer archived so it is read-write again.
  def unset_archived(synchronous: false)
    return true if maintained?

    begin
      orchestration = RepositoryOrchestration.unarchive(T.cast(self, Repository), actor: actor) # rubocop:todo GitHub/AvoidCast

      if orchestration.valid?
        orchestration.execute(synchronous:)
        return true
      end

      GitHub.logger.info(
        "Unarchive Repository Failed",
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.request_id" => GitHub.context[:request_id],
        "gh.repo.orchestration.id" => orchestration.id,
        "gh.repo.orchestration.state" => orchestration.state,
        "gh.repo.orchestration.repository.errors" => orchestration.errors&.where(:repository)&.map { |e| e.message }&.join(", "),
        "gh.repo.id" => self.id
      )

      false
    ensure
      reset_archived
    end
  end

  def unarchive_blocked?
    owner&.organization? && owner&.archived?
  end

  private def reset_archived
    remove_instance_variable(:@archived) if defined?(@archived)
    clear_preloaded_batch_method_value(:archived?)
  end
end
