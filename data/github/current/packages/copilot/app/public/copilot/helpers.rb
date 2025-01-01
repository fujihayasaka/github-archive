# typed: strict
# frozen_string_literal: true

module Copilot
  module Helpers
    extend T::Helpers
    include Copilot::Signatures

    abstract!

    # Simple wrapper for connecting to read for read operations only.
    sig do
      type_parameters(:A).params(
        block: T.proc.returns(T.type_parameter(:A)),
      ).returns(T.type_parameter(:A))
    end
    def self.with_read(&block)
      GitHub.dogstats.increment("copilot.with_read")
      ActiveRecord::Base.connected_to(role: :reading) do
        yield
      end
    end

    # Simple wrapper for connecting to write for write operations only.
    sig do
      type_parameters(:A).params(
        block: T.proc.returns(T.type_parameter(:A)),
      ).returns(T.type_parameter(:A))
    end
    def self.with_write(&block)
      GitHub.dogstats.increment("copilot.with_write")
      ActiveRecord::Base.connected_to(role: :writing) do
        yield
      end
    end

    sig do
      type_parameters(:A)
        .params(lock_key: String, block: T.proc.returns(T.type_parameter(:A)))
        .returns(T.type_parameter(:A))
    end
    def self.lock(lock_key, &block)
      restraint = GitHub::Restraint.new
      restraint.lock!(lock_key, 1, 5.minutes) do
        block.call
      end
    end

    sig { params(msg: String, room_id: T.nilable(String)).void }
    def self.chatterbox_say(msg, room_id: nil)
      return unless GitHub.copilot_enabled?
      return unless FeatureFlag.vexi.enabled_or_raise?(:copilot_chatterbox) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

      Copilot::Helpers.force_chatterbox_say!(msg, room_id: room_id, directly_called: false)
    end

    sig { params(msg: String, room_id: T.nilable(String), directly_called: T::Boolean).void }
    def self.force_chatterbox_say!(msg, room_id: nil, directly_called: true)
      room_id ||= Copilot::DEFAULT_SLACK_CHANNEL

      GitHub::Chatterbox.client.say!(room_id, msg)
      GitHub.logger.info(
        "Chatterbox sent",
        "gh.chatterbox.message" => msg,
        "gh.chatterbox.channel" => room_id,
      )
    end

    # this sends message to our fun slack channel
    sig { override.params(msg: String, room_id: T.nilable(String)).void }
    def chatterbox_say(msg, room_id: nil)
      Copilot::Helpers.chatterbox_say(msg, room_id: room_id)
    end

    # Simple wrapper for connecting to read for read operations only.
    sig do
      override.type_parameters(:A).params(
        block: T.proc.returns(T.type_parameter(:A)),
      ).returns(T.type_parameter(:A))
    end
    def with_read(&block)
      GitHub.dogstats.increment("copilot.with_read")
      ActiveRecord::Base.connected_to(role: :reading) do
        yield
      end
    end

    # Simple wrapper for connecting to write for write operations only.
    sig do
      override.type_parameters(:A).params(
        block: T.proc.returns(T.type_parameter(:A)),
      ).returns(T.type_parameter(:A))
    end
    def with_write(&block)
      GitHub.dogstats.increment("copilot.with_write")
      ActiveRecord::Base.connected_to(role: :writing) do
        yield
      end
    end
  end
end
