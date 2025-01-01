# typed: false
# frozen_string_literal: true

module Repository::ArchivedDependency
  def self.included(base)
    base.scope :archived_scope,             -> { where(maintained: false) }
    base.scope :not_archived_scope,         -> { where(maintained: true) }
  end

  # Public: Query if a repository is archived (read-only).
  def archived?
    async_archived?.sync
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
      orchestration = RepositoryOrchestration.archive(self, actor: actor)

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
      orchestration = RepositoryOrchestration.unarchive(self, actor: actor)

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
    owner.organization? && owner.archived?
  end

  def toggle_security_product_on_archive(actor)
    SecurityProduct::ServiceManager.new(self).toggle_services_on_repository_marked_as_archived(actor: actor)
  end

  private def reset_archived
    remove_instance_variable(:@archived) if defined?(@archived)
  end
end
