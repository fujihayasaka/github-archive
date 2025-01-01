# typed: true
# frozen_string_literal: true

require "chatterbox-client"

module GitHub
  module Chatterbox
    class Silent
      def say(topic, message); end
      def say!(topic, message); end
    end

    # Public: Return the correct Chatterbox client, depending on if it is enabled or not
    def self.client
      if GitHub.chatterbox_enabled?
        ::Chatterbox::Client
      else
        muted_chatterbox
      end
    end

    # Internal: return a faked out Chatterbox that does nothing
    def self.muted_chatterbox
      @muted_chatterbox ||= Silent.new
    end

    # Mute Chatterbox for the duration of the block
    def self.mute
      original, GitHub.chatterbox_enabled = GitHub.chatterbox_enabled?, false
      yield if block_given?
    ensure
      GitHub.chatterbox_enabled = original
    end

    # Unmute Chatterbox for the duration of the block
    def self.unmute
      original, GitHub.chatterbox_enabled = GitHub.chatterbox_enabled?, true
      yield if block_given?
    ensure
      GitHub.chatterbox_enabled = original
    end
  end
end
