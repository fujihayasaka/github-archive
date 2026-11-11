# typed: true
# frozen_string_literal: true

require "msgpack"

module GitHub::DataStructures

  # A Persistent Atomic Queue is a thread-safe queue persisted in a Key-value store
  # (by default GitHub.kv) and thus bounded to the size of the value size allowed
  # by the store itself (by default 64KB which is the size of GitHub's KV BLOB value)
  #
  # Concurrent access is controlled by a Redis MutexGroup to allow a single consumer
  # to access concurrently a queue instance.
  #
  # The following are the arguments required to initialize a queue:
  #
  # * `:queue_type`, A string used to namespace queues of the same type in the
  #  persistent storage
  # * `:queue_name`, The name of the queue. Queues with the same type and name
  #  will access the same memory in the datastore.
  # * `:payload_class`, A class able to do marshalling / unmarshalling via
  # `#to_hash` and `.from_hash` methods.
  #
  # Optionally, you can provide:
  #
  #  * `:store`, An adapter of a KV store with methods `get`, `set`, `del`, `exist`.
  #  The default store is `GitHub.kv
  #  * `:serializer`, A object to do marshalling/unmarshalling of hash objects into
  #  binary representations and vicevrsa. By default we use LZ4 compressed,
  #  MessagePack payloads
  #
  # TODO: `queue_type` and `queue_name` denote the identity of a queue. As of today,
  # there's no code protecting from users of this data structure to initialize
  # two instances of the queue with different configuration. A persisted registry
  # of queues should be implemented to prevent wrong useages from happening
  #
  class PersistentAtomicQueue
    class OverflowError < StandardError
      attr_reader :queue_type, :queue_name, :element_count, :size_in_bytes, :max_size_in_bytes

      def initialize(queue_type, queue_name, element_count, size_in_bytes, max_size_in_bytes)
        super("Tried to store #{element_count} elements for queue (#{queue_type}/#{queue_name}). Serialized queue size is #{size_in_bytes} bytes long, but only #{max_size_in_bytes} bytes can be stored")
        @queue_type = queue_type
        @queue_name = queue_name
        @element_count = element_count
        @size_in_bytes = size_in_bytes
        @max_size_in_bytes = max_size_in_bytes
      end
    end

    DEFAULT_STORE = GitHub.kv # rubocop:todo GitHub/DoNotUseGlobalKv
    DEFAULT_SERIALIZER = Coders.compose(MessagePack, Coders::LZ4, default: [])

    DEFAULT_MAX_BYTES = 64.kilobytes   # We can only store pending moves that serialized are as long as the width of BLOB column

    LOCK_TIMEOUT_SECS = 300            # So the lock gets cleared if the process is killed after it's been acquired (i.e. in case of a request timeout)
    LOCK_WAIT_SECS    = 2              # Used when `lock_with_retry` or `lock` are called. It will try up to this time in seconds to acquire the lock. (Only used in jobs)
    LOCK_SLEEP_SECS   = 0.2            # Sleep 200 millis if `lock_with_retry` or `lock` are called.

    attr_reader :queue_type, :queue_name, :payload_class, :store, :serializer, :max_bytes

    def initialize(queue_type:, queue_name:, payload_class:, store: DEFAULT_STORE, serializer: DEFAULT_SERIALIZER, max_bytes: DEFAULT_MAX_BYTES)
      @queue_type = queue_type
      @queue_name = queue_name
      @payload_class = payload_class
      @store = store
      @serializer = serializer
      @max_bytes = max_bytes
    end

    # Enqueues a payload_class instance
    #
    # payload is a payload_class instance
    #
    # Returns nothing
    #
    def enqueue(payload)
      unless payload.is_a? payload_class
        raise ArgumentError, "#{payload} has to be an instance of #{payload_class}"
      end

      lock.lock do
        store! load!.push(payload.to_hash)
      end
    end

    # Gets the payload_class instance at the head of the queue without removing it
    #
    # Returns payload_class
    #
    def peek
      lock.lock do
        head = load!.first
        head && payload_class.from_hash(**head)
      end
    end

    # Returns the payload_class instance at the head of the queue after removing it from it
    #
    # Returns payload_class
    #
    def dequeue
      lock.lock do
        queue = load!
        head = queue.shift

        if queue.empty?
          destroy_without_lock
        else
          store!(queue, check_size: false)
        end

        head && payload_class.from_hash(**head)
      end
    end

    # Determines whether there exist a queue of pending changes
    #
    # Returns Boolean
    def exist?
      lock.lock do
        store.exists(queue_key).value!
      end
    end

    # Deletes the queue, removing the key from redis
    #
    # Returns nothing
    def destroy
      lock.lock do
        destroy_without_lock
      end
    end

    def to_a
      load!.map { |el| payload_class.from_hash(**el) }
    end

    # Gets the number of elements in the queue
    #
    # Returns integer
    def size
      to_a.size
    end
    alias_method :length, :size
    alias_method :count,  :size

    private

    def load!
      @serializer.load store.get(queue_key).value!
    end

    def store!(queue, check_size: true)
      value = GitHub::KV::BINARY(@serializer.dump(queue))

      # We're maintaining compatibility with the github-ds implementation here,
      # which was (presumably inadvertently) counting the bytesize of the
      # hex-encoded value.
      #
      # This should almost certainly change to directly counting value.bytesize
      # in future, but we'll need to decide whether we want to enforce the
      # originally-intended maximum, or the current effective maximum value
      # (max_bytes / 2)
      #
      # See https://github.com/github/github-ds/blob/c5962e5f59ea97924278a01ea8d85edd29aa2386/lib/github/sql.rb#L69
      value_byte_size = value.is_a?(GitHub::SQL::Literal) ? value.bytesize : value.bytesize * 2

      if check_size && value_byte_size >= max_bytes
        raise OverflowError.new(queue_type, queue_name, queue.length, value_byte_size, max_bytes)
      end

      store.set(queue_key, value)
    end

    def destroy_without_lock
      store.del(queue_key)
    end

    def queue_key
      @queue_key ||= "%s/%s" % [queue_type, queue_name]
    end

    def lock
      @lock ||= GitHub::Redis::MutexGroup.new(queue_type, queue_name, timeout: LOCK_TIMEOUT_SECS, wait: LOCK_WAIT_SECS, sleep: LOCK_SLEEP_SECS)
    end
  end
end
