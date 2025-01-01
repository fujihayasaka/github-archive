# typed: false
# frozen_string_literal: true

require "sorbet-runtime"

module ActiveJob
  module LockingJob
    extend ActiveSupport::Concern
    extend T::Helpers

    DEFAULT_LOCK_TIMEOUT = 60 * 60 # 1 hour
    DEFAULT_LOCK_KEY = "key"

    # Lock jobs by unique arguments by default.
    DEFAULT_LOCK_PROC = proc do |job|
      if job.arguments.empty?
        DEFAULT_LOCK_KEY
      else
        DEFAULT_LOCK_STRINGIFY_PROC.call(job.arguments)
      end
    end

    # Predictably stringify job arguments, including AR models.
    DEFAULT_LOCK_STRINGIFY_PROC = proc do |args|
      args.map do |obj|
        case obj
        when ApplicationRecord::Base
          "#{obj.class.name}#{obj.id}"
        when Hash
          transformed = obj.transform_values do |value|
            DEFAULT_LOCK_STRINGIFY_PROC.call([value])
          end
          sorted = transformed.to_a.sort_by { |x| x.first.to_s }.join(",")
          "{#{sorted}}"
        when Array
          "[#{obj.map { |o| DEFAULT_LOCK_STRINGIFY_PROC.call([o]) }.join(",")}]"
        else
          obj.to_s
        end
      end.join(" ")
    end

    included do
      attr_writer :lock_key

      class_attribute :_lock_key, instance_accessor: false
      class_attribute :_lock_timeout, instance_accessor: false

      around_enqueue do |job, block|
        # Skip enqueueing if this job is a locking job and we can't acquire the lock.
        if job.locking? && !job.acquire_lock
          GlobalInstrumenter.instrument("jobs.lock-not-acquired", { job: job })
          next
        end

        block.call
      end

      around_perform do |job, block|
        unless job.locking?
          block.call
          next
        end

        begin
          block.call
          job.clear_lock
        rescue StandardError, Aqueduct::Worker::JobKilled => exception # rubocop:todo Lint/GenericRescue
          # The exception handling in the parent may trigger a re-enqueue of the
          # job so we need to make sure the lock is cleared before it runs.
          job.clear_lock
          raise exception
        end
      end
    end

    module ClassMethods
      def lock_key
        self._lock_key
      end

      # The name of the "lock set" where the key derived from arguments will be
      # set to implement locking.  Defaults to the name of the class.
      def lock_set_name
        self.name
      end

      def lock_timeout
        self._lock_timeout.to_i
      end

      def locked_by(key:, timeout:)
        self._lock_key = key
        self._lock_timeout = timeout
      end
    end
    mixes_in_class_methods(ClassMethods)

    def serialize
      super.tap do |obj|
        obj["lock_key"] = lock_key
      end
    end

    def deserialize(job_data)
      super(job_data)
      self.lock_key = job_data["lock_key"]
    end

    def lock_key
      return nil unless self.class.lock_timeout > 0 && self.class.lock_key.present?
      @lock_key ||= begin
        key = self.class.lock_key.call(self)
        key = DEFAULT_LOCK_STRINGIFY_PROC.call([key]) unless key.is_a?(String)
        key
      end
    end

    def safe_lock_key
      return nil unless lock_key.present?
      @safe_lock_key ||= Digest::SHA256.hexdigest(lock_key)
    end

    def locking?
      lock_key.present?
    end

    delegate :acquire_lock, :clear_lock, :locked?, to: :hash_lock

    private

    def hash_lock
      @hash_lock ||= JobHashLock.new(self)
    end
  end
end
