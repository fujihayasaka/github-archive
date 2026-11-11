# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Instrumentation
  # This class builds backend feature flags for instrumentation / service calls for Gists
  # These flags are typically used by Token Scanning Service (TSS)
  class GistServiceFlags
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(gist: Gist).void }
    def initialize(gist)
      @gist = gist
      @public_scanning = SecretScanning::Features::Gist::PublicScanning.new(@gist)
    end

    sig { returns(T::Array[String]) }
    def gist_scanning_service_flags
      flags = []
      return flags unless @public_scanning.enabled?

      flags << ServiceFlags::TOKEN_SCANNING_SERVICE_INGEST
      flags << ServiceFlags::COMMIT_METADATA_SCANNING

      flags
    end
  end
end
