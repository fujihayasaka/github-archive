# typed: true
# frozen_string_literal: true

module Codespaces
  class FindEnvironment < Command
    class NotFoundError < StandardError; end

    attr_reader :codespace, :lock_key

    def self.call(codespace)
      new(codespace).call
    end

    def self.call!(codespace)
      new(codespace).call!
    end

    def initialize(codespace)
      @codespace = codespace
    end

    def call!
      GitHub.tracer.in_span("#{name}#call!", kind: :internal) do |_span|
        perform
      end
    end

    def call
      super
    rescue NotFoundError
      nil
    end

    def perform
      client.list_environments(name: codespace.name).first or raise NotFoundError, "Environment not found"
    rescue Codespaces::Client::TimeoutError => e
      raise NotFoundError.new(e)
    end

    private

    def client
      @client ||= Codespaces::VscsClient.for_codespace(
        codespace,
        timeouts: { open_timeout: 2, timeout: 10 }
      )
    end
  end
end
