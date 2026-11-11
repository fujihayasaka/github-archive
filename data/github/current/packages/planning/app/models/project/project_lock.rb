# typed: false
# frozen_string_literal: true

# Utility module for managing Project locks based on bulk actions to the Project
# or the contents of a Project. Locks have two components: the lock type/reason
# and the job context. The job context allows us to perform operations on the
# Project while it is locked, but prevents the user from doing anything in the
# UI and APIs.
#
# If a user tries to perform an operation on a locked Project, they will see a
# ContentAuthorizationError::ProjectLocked error raised.
#
# ADDING A NEW LOCK TYPE
#
# 1. Create a new constant for the lock type
# 2. Add the lock type and job context to LOCK_CONTEXT
# 3. You are IN BUSINESS
# 4. ... but maybe write some tests
#
# IMPORTANT: once you create a new lock type, you should NEVER change the keys
# for "lock_type" and "job_context". Changing EITHER of these keys will cause
# any locked Projects to remain locked in a limbo state and people will be SAD.
#
# LOCKING A PROJECT
# This works in most scenarios!
#
# project.lock!(lock_type: PROJECT_CLONING, actor: user)
# (or any other valid lock type)
#
# LOCKING A PROJECT SAFELY
# If you need to yield a block that enqueues further jobs, use this!
#
# project.lock_safely(lock_type: PROJECT_RESYNCING, actor: user) do { ... }
# (or any other valid lock type)
#
# UNLOCKING A PROJECT FOR A SINGLE REASON
#
# project.unlock(PROJECT_CLONING)
# (or any other valid lock type)
#
# UNLOCKING A PROJECT FROM ALL LOCK TYPES
#
# project.unlock!
#

class Project
  module ProjectLock
    extend self

    class InvalidLockReasonError < StandardError; end

    PROJECT_CLONING = "project_cloning".freeze
    CARD_ARCHIVING = "project_card_archiving".freeze
    PROJECT_RESYNCING = "project_resyncing".freeze
    NEW_PROJECT_IMPORT = "project_importing".freeze

    LOCK_CONTEXT = {
      "#{PROJECT_CLONING}" => {
        lock_type: PROJECT_CLONING,
        job_context: :clone_project_from_job,
      },
      "#{CARD_ARCHIVING}" => {
        lock_type: CARD_ARCHIVING,
        job_context: :project_archive_cards_from_job,
      },
      "#{PROJECT_RESYNCING}" => {
        lock_type: PROJECT_RESYNCING,
        job_context: :project_resyncing,
      },
      "#{NEW_PROJECT_IMPORT}" => {
        lock_type: NEW_PROJECT_IMPORT,
        job_context: :project_import_from_job,
      },
    }.freeze

    def lock_key(lock_type)
      "#{lock_type}:#{id}"
    end

    def locked?
      LOCK_CONTEXT.keys.any? do |lock_type|
        Memex::KV.store.get(lock_key(lock_type)).value { false }
      end
    end

    def locked_for?(lock_type)
      raise InvalidLockReasonError unless valid_reason?(lock_type)
      Memex::KV.store.get(lock_key(lock_type)).value { false }
    end

    def lock!(lock_type:, actor:)
      return if locked_for?(lock_type)
      raise InvalidLockReasonError unless valid_reason?(lock_type)

      Memex::KV.store.set(lock_key(lock_type), actor.display_login)
      notify_metadata_subscribers(locked_by: actor.display_login)
    end

    def lock_safely(lock_type:, actor:)
      begin
        lock!(lock_type: lock_type, actor: actor)
        yield
      ensure
        unlock(lock_type)
      end
    end

    def unlock(lock_type)
      raise InvalidLockReasonError unless valid_reason?(lock_type)
      Memex::KV.store.del(lock_key(lock_type))
      notify_metadata_subscribers(locked_by: false)
    end

    def unlock!
      LOCK_CONTEXT.keys.each do |lock_type|
        Memex::KV.store.del(lock_key(lock_type))
      end
      notify_metadata_subscribers(locked_by: false)
    end

    def job_context?(lock_type)
      raise InvalidLockReasonError unless valid_reason?(lock_type)
      job_context = LOCK_CONTEXT[lock_type][:job_context]
      GitHub.context[job_context].present?
    end

    def set_job_context(lock_type)
      raise InvalidLockReasonError unless valid_reason?(lock_type)
      job_context = LOCK_CONTEXT[lock_type][:job_context]
      GitHub.context.push(job_context.to_sym => id)
    end

    private

    def valid_reason?(lock_type)
      LOCK_CONTEXT.keys.include?(lock_type)
    end
  end
end
