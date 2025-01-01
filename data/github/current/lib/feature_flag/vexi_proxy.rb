# typed: strict
# frozen_string_literal: true

require "vexi"

module FeatureFlag
  # This class wraps the vexi singleton with a wrapper that can fallback to flipper in case of issues during the migration.
  class VexiProxy
    extend T::Helpers
    extend T::Sig

    include Kernel

    sig { params(vexi_proc: T.proc.returns(Vexi::Client)).void }
    def initialize(vexi_proc)
      @vexi_proc = T.let(vexi_proc, T.proc.returns(Vexi::Client))
    end

    sig do
      params(
        name: T.any(String, Symbol),
        actors: T.all(GitHub::IFlipperActor, T.any(String, Vexi::Actor))
      )
      .returns(T::Boolean)
    end
    def enabled?(name, *actors)
      if GitHub.flipper.enabled?(:vexi_enabled)
        begin
          T.unsafe(vexi).enabled?(name, *actors)
        rescue StandardError => ex # rubocop:disable Lint/GenericRescue
          if GitHub::AppEnvironment.test? || ENV["GITHUB_CI"]
            raise ex
          end
          GitHub.dogstats.increment("gh.vexi_proxy.unhandled_exception", tags: ["feature:#{name}"])
          Failbot.report(ex, feature: name)

          check_flipper(name, actors)
        end
      else
        check_flipper(name, actors)
      end
    end

    sig { params(value: T::Boolean).void }
    def memoize=(value)
      vexi.memoize = value
    end

    sig { returns(T::Boolean) }
    def memoizing?
      vexi.memoizing?
    end

    sig { params(names: T::Array[T.any(::String, ::Symbol)], fetch_directly_from_adapter: T::Boolean).void }
    def preload(names, fetch_directly_from_adapter: T.unsafe(nil))
      vexi.preload(names, fetch_directly_from_adapter: fetch_directly_from_adapter)
    end

    private

    sig { returns(Vexi::Client) }
    def vexi
      @vexi_proc.call
    end

    sig do
      params(
        name: T.any(String, Symbol),
        actors: T::Array[T.all(GitHub::IFlipperActor, T.any(String, Vexi::Actor))]
      )
      .returns(T::Boolean)
    end
    def check_flipper(name, actors)
      # If actors are empty, check flipper without actors
      if actors.empty?
        return GitHub.flipper.enabled?(name)
      end

      # Loop through all actors and check if enabled via flipper.
      actors.each do |actor|
        return true if GitHub.flipper.enabled?(name, actor)
      end

      false
    end
  end
end
