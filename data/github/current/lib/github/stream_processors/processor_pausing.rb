# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module ProcessorPausing
      extend ActiveSupport::Concern

      included do
        set_callback :open, :before do
          sleep(1) while paused? && !shutting_down?
        end

        set_callback :close, :after do
          @shutting_down = true
        end
      end

      # Includes methods for allowing a processor to Pause/Resume their message processing
      # See https://github.com/devtools/stream_processors for UI on using this functionality.
      #
      # These class methods may be overridden to provide different approaches to pausing and resuming
      # but all of them MUST be overridden if one is changed.
      class_methods do

        sig { returns(T.nilable(String)) }
        def slack_pause_notifications_channel
          @slack_pause_notifications_channel
        end

        sig { params(channel: T.nilable(String)).returns(T.nilable(String)) }
        def slack_pause_notifications_channel=(channel)
          @slack_pause_notifications_channel = channel
        end

        # Public: Pause a processor with the given pause key.
        #
        # This method can be overridden by subclasses to provide their own pause/resume implementation.
        # If this method is overridden then resume, paused?, and paused_at must be overridden as well.
        # An exception is always raised to force the processor process to restart to ensure messages
        # are not lost.
        #
        # pause_key - A String key used to set the pause record for the processor.
        # expires   - Optional Time expiration that will be used to automatically expire the pause
        # raise_immediately - Optional Boolean whether or not to immediately raise a
        #                     ::GitHub::StreamProcessors::ProcessorPausedError (default true)
        #
        # Returns nothing
        # Raises GitHub::StreamProcessors::ProcessorPausedError
        def pause(pause_key, reason:, expires: nil, raise_immediately: true)
          ActiveRecord::Base.connected_to(role: :writing) do
            # rubocop:todo GitHub/DoNotUseGlobalKv
            GitHub.kv.set("processor-paused-#{pause_key}", { at: Time.current, reason: reason, expires: expires }.to_json, expires: expires)
            # rubocop:enable GitHub/DoNotUseGlobalKv
          end
          send_pause_notification(pause_key, expires, reason)
          raise ::GitHub::StreamProcessors::ProcessorPausedError if raise_immediately
        end

        # Public: Resume a processor with the given pause key.
        #
        # This method can be overridden by subclasses to provide their own pause/resume implementation.
        # If this method is overridden then pause, paused?, and paused_at must be overridden as well
        #
        # pause_key - A String key used to set the delete the pause record for the processor.
        #
        # Returns nothing
        def resume(pause_key)
          ActiveRecord::Base.connected_to(role: :writing) do
            GitHub.kv.del("processor-paused-#{pause_key}") # rubocop:todo GitHub/DoNotUseGlobalKv
          end
          send_resume_notification(pause_key)
        end

        # Public: Checks whether the given pause key exists and the processor is paused
        #
        # This method can be overridden by subclasses to provide their own pause/resume implementation.
        # If this method is overridden then pause, resume, and paused_at must be overridden as well
        #
        # pause_key - A String key used to check whether the pause key has been set.
        #
        # Returns Boolean
        def paused?(pause_key)
          ActiveRecord::Base.connected_to(role: :reading) do
            GitHub.kv.exists("processor-paused-#{pause_key}").value! # rubocop:todo GitHub/DoNotUseGlobalKv
          end
        end

        # Public: Returns the Time when the pause key was set or paused
        #
        # This method can be overridden by subclasses to provide their own pause/resume implementation.
        # If this method is overridden then pause, resume, and paused? must be overridden as well
        #
        # pause_key - A String key used to check when the processor was pause
        #
        # Returns Time
        def paused_at(pause_key)
          raw_value = GitHub.kv.get("processor-paused-#{pause_key}").value! # rubocop:todo GitHub/DoNotUseGlobalKv
          return unless raw_value

          data = JSON.parse(raw_value, symbolize_names: true)
          Time.parse(data[:at])
        end

        # Public: Returns the reason for the processor being paused (or nil if it isn't paused)
        #
        # This method can be overridden by subclasses to provide their own pause/resume implementation.
        # If this method is overridden then pause, resume, and paused? must be overridden as well
        #
        # pause_key - A String key used to check when the processor was pause
        #
        # Returns Time
        def pause_reason(pause_key)
          raw_value = GitHub.kv.get("processor-paused-#{pause_key}").value! # rubocop:todo GitHub/DoNotUseGlobalKv
          return unless raw_value

          JSON.parse(raw_value, symbolize_names: true).dig(:reason)
        end

        # Public: Returns the Time when the pause key is set to expire (if expiry is set)
        #
        # This method can be overridden by subclasses to provide their own pause/resume implementation.
        # If this method is overridden then pause, resume, and paused? must be overridden as well
        #
        # pause_key - A String key used to check when the pause will expire
        #
        # Returns Time
        def resumes_at(pause_key)
          raw_value = GitHub.kv.get("processor-paused-#{pause_key}").value! # rubocop:todo GitHub/DoNotUseGlobalKv
          return unless raw_value

          data = JSON.parse(raw_value, symbolize_names: true)
          Time.parse(data[:expires]) if data[:expires].present?
        end

        def send_pause_notification(pause_key, expires, reason)
          if slack_pause_notifications_channel.present? && send_notification?(pause_key)
            message = "Pausing #{pause_key}. Reason: #{reason}"
            message += " - Automatically resumes: #{expires.iso8601}" if expires.present?
            key = notification_key(pause_key)
            GitHub.kv.set(key, Time.current.to_s, expires: expires) # rubocop:todo GitHub/DoNotUseGlobalKv
            GitHub::Chatterbox.client.say!(slack_pause_notifications_channel, message)
          end
        end

        def send_resume_notification(pause_key)
          if slack_pause_notifications_channel.present?
            GitHub::Chatterbox.client.say!(slack_pause_notifications_channel, "Resuming #{pause_key}")
            key = notification_key(pause_key)
            GitHub.kv.del(key) # rubocop:todo GitHub/DoNotUseGlobalKv
          end
        end

        def notification_key(pause_key)
          "processor-pause-notification-#{pause_key}"
        end

        def send_notification?(pause_key)
          key = notification_key(pause_key)
          !GitHub.kv.exists(key).value { false } # rubocop:todo GitHub/DoNotUseGlobalKv
        end
      end

      # Public: Pause the processor by its pause key which by default is the group ID.
      #
      # To change the implementation of pausing and resuming the class method should be overridden
      #
      # reason    - Required String reason for pausing the processor
      # expires   - Optional Time expiration that will be used to automatically expire the pause
      # raise_immediately - Optional Boolean whether or not to immediately raise a
      #                     ::GitHub::StreamProcessors::ProcessorPausedError (default true)
      #
      # Returns nothing
      # Raises GitHub::StreamProcessors::ProcessorPausedError
      def pause(reason:, expires: nil, raise_immediately: true)
        self.class.pause(pause_key, reason: reason, expires: expires, raise_immediately: raise_immediately)
      end

      # Public: Resumes the processor by its resume key which by default is the group ID.
      #
      # To change the implementation of pausing and resuming the class method should be overridden
      #
      # Returns nothing
      def resume
        self.class.resume(pause_key)
      end

      # Public: Returns whether the processor is paused
      #
      # To change the implementation of pausing and resuming the class method should be overridden
      #
      # Returns Boolean
      def paused?
        self.class.paused?(pause_key)
      end

      # Public: Returns the time when the processor was paused or nil if it's processing
      #
      # To change the implementation of pausing and resuming the class method should be overridden
      #
      # Returns Time | Nil
      def paused_at
        self.class.paused_at(pause_key)
      end

      # Public: Returns the reason the processor was paused (or nil if it isn't paused)
      #
      # To change the implementation of pausing and resuming the class method should be overridden
      #
      # Returns String | Nil
      def pause_reason
        self.class.pause_reason(pause_key)
      end

      # Public: Returns the time when the processor will resume or nil if it's processing or paused indefinitely
      #
      # To change the implementation of pausing and resuming the class method should be overridden
      #
      # Returns Time | Nil
      def resumes_at
        self.class.resumes_at(pause_key)
      end

      def pause_key
        group_id
      end

      private

      # Internal: Check if processor is shutting down
      #
      # Returns Boolean
      def shutting_down?
        !!@shutting_down
      end
    end
  end
end
