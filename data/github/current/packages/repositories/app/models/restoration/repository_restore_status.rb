# typed: true
# frozen_string_literal: true

module Restoration
  class RepositoryRestoreStatus
    include GitHub::Memoizer

    COMPLETED_MESSAGE = "Done!"
    FAILED_MESSAGE = "Unable to complete this job..."
    QUEUED_MESSAGE = "Queued..."
    MISSING_REPOSITORY_MESSAGE = "Finished? No Repository was found though..."

    def self.for(repository_id:)
      new(repository_id)
    end

    def initialize(repository_id)
      @repository_id  = repository_id
    end

    # Public: Gets the current message describing the state of this job.
    #
    # Returns a String.
    def message
      data = orchestration&.data
      message = data && data.dig(:message)
      return QUEUED_MESSAGE if message.nil? && (orchestration && !orchestration&.finished?)
      message
    end

    def set_message(message)
      orchestration.update(data: orchestration.data.merge(message:))
    end

    # Public: Gets the HTTP status for this job.
    #
    # Return a Symbol status for Rails, like :ok.
    def status
      if orchestration.nil? || orchestration.succeeded? || orchestration.failed?
        :ok
      else
        :accepted
      end
    end

    def reset_message
      orchestration.update(data: orchestration.data.merge(message: nil))
    end

    def message=(message)
      set_message(message)
    end

    # Public: Clears the message and lock only if the message is not pending.
    # Pending messages have an ellipsis in them ("...").
    #
    # Returns true if the message was reset, or false.
    def reset_message_if_finished
      return false if message.nil?
      return false if message["..."]
      ActiveRecord::Base.connected_to(role: :writing) { reset_message }
      true
    end

    def set_default_message
      set_message(default_message)
    end

    def default_message
      if status == :ok
        if FeatureFlag.vexi.enabled?(:repos_domain_stafftools, default: false)
          return Repositories.domain.active_by_id(@repository_id.to_i) ? COMPLETED_MESSAGE : MISSING_REPOSITORY_MESSAGE
        else
          repo = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
            Repositories.domain.active_by_id(@repository_id.to_i)
          else
            Repository.find_by(id: @repository_id, active: true)
          end
          return repo ? COMPLETED_MESSAGE : MISSING_REPOSITORY_MESSAGE
        end
      end

      QUEUED_MESSAGE
    end

    def safe_message
      message || default_message
    end

    private

    memoize def repository
      if FeatureFlag.vexi.enabled?(:repos_domain_stafftools, default: false)
        Repositories.domain.by_id(@repository_id.to_i)
      else
        Repository.find_by(id: @repository_id)
      end
    end

    def orchestration
      RestoreRepositoryOrchestration.most_recent_restore_orchestration_for(repository:)
    end
  end
end
