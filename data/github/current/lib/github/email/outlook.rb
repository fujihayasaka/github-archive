# typed: strict
# frozen_string_literal: true

module GitHub
  module Email
    # Outlook-specific email header utilities.
    #
    # Provides helpers for generating the proprietary Thread-Index and
    # Thread-Topic headers that Microsoft Outlook / Exchange use for
    # conversation grouping (see MS-OXCMAIL §2.2.3.2).
    module Outlook
      # The Windows FILETIME epoch offset from Unix epoch.
      # FILETIME counts 100-nanosecond intervals since 1601-01-01.
      # Unix epoch is 1970-01-01. Difference is 11644473600 seconds.
      FILETIME_EPOCH_OFFSET = 11_644_473_600

      # 1 second = 10,000,000 100-nanosecond intervals (FILETIME units).
      FILETIME_TICKS_PER_SECOND = 10_000_000

      # Generate a Thread-Index header value for an email notification.
      #
      # The Thread-Index is a Base64-encoded binary value used by Microsoft
      # Outlook to group emails into conversations per the MAPI specification
      # (PidTagConversationIndex). It consists of:
      #   - A 22-byte root header (1 reserved + 5 FILETIME + 16 GUID)
      #   - Optional 5-byte child blocks appended for replies
      #
      # thread_key  - A stable String identifying the conversation
      #               (e.g., the issue/PR message_id)
      # created_at  - The Time the conversation started (issue/PR creation time)
      # reply_time  - The Time of the reply event. When present, a 5-byte child
      #               block is appended to mark this as a reply.
      #
      # Returns a Base64-encoded String suitable for the Thread-Index header.
      sig do
        params(
          thread_key: String,
          created_at: Time,
          reply_time: T.nilable(Time),
        ).returns(String)
      end
      def self.thread_index(thread_key:, created_at:, reply_time: nil)
        guid_bytes = deterministic_guid(thread_key)
        filetime_bytes = to_filetime_bytes(created_at)

        # Root header: 1 reserved byte (0x01) + 5 most-significant FILETIME bytes + 16-byte GUID
        header = String.new(encoding: ::Encoding::BINARY)
        header << [0x01].pack("C")
        header << filetime_bytes
        header << guid_bytes

        if reply_time
          header << child_block(created_at, reply_time)
        end

        Base64.strict_encode64(header)
      end

      # Derive a stable Thread-Topic value from an RFC 2822 message_id.
      #
      # Strips the angle brackets and @host suffix so the topic is a
      # human-readable path that stays constant across title renames:
      #   "<owner/repo/issues/123@github.com>" → "owner/repo/issues/123"
      #
      # message_id - An RFC 2822 Message-Id string (e.g., from Issue#message_id)
      #
      # Returns a String suitable for the Thread-Topic header.
      sig { params(message_id: String).returns(String) }
      def self.thread_topic(message_id)
        message_id.sub(/\A</, "").sub(/@[^>]*>?\z/, "")
      end

      # Generate a deterministic 16-byte GUID from a thread key.
      sig { params(thread_key: String).returns(String) }
      def self.deterministic_guid(thread_key)
        Digest::SHA256.digest(thread_key)[0, 16]
      end
      private_class_method :deterministic_guid

      # Convert a Ruby Time to the 5 most-significant bytes of a Windows FILETIME.
      sig { params(time: Time).returns(String) }
      def self.to_filetime_bytes(time)
        filetime = (time.to_i + FILETIME_EPOCH_OFFSET) * FILETIME_TICKS_PER_SECOND
        [filetime].pack("Q>")[0, 5]
      end
      private_class_method :to_filetime_bytes

      # Generate a 5-byte child block encoding the time delta from root.
      #
      # Per MS-OXOMSG §2.2.1.3:
      #   - 1 bit: response level (0 for normal)
      #   - 31 bits: time delta from root in FILETIME units, right-shifted by 18
      #   - 8 bits: random component
      sig { params(root_time: Time, reply_time: Time).returns(String) }
      def self.child_block(root_time, reply_time)
        delta_seconds = [reply_time.to_i - root_time.to_i, 0].max
        delta_filetime = delta_seconds * FILETIME_TICKS_PER_SECOND
        # Right-shift by 18 bits per spec, mask to 31 bits
        delta_value = (delta_filetime >> 18) & 0x7FFFFFFF
        # Pack as big-endian 32-bit unsigned int (4 bytes) + 1 random byte
        [delta_value].pack("N") + [SecureRandom.random_number(256)].pack("C")
      end
      private_class_method :child_block
    end
  end
end
