# typed: strict
# frozen_string_literal: true

module SecretScanning::Instrumentation
  # This class builds backend feature flags for instrumentation / service calls for Owners
  # These flags are typically used by Token Scanning Service (TSS)
  class OwnerServiceFlags
    extend T::Sig

    sig { params(owner: T.any(Organization, Business, User)).void }
    def initialize(owner)
      @owner = owner
      @content_scanning = T.let(SecretScanning::Features::Owner::ContentScanning.new(@owner), SecretScanning::Features::Owner::ContentScanning)
      @wiki_scanning = T.let(SecretScanning::Features::Owner::WikiScanning.new(@owner), SecretScanning::Features::Owner::WikiScanning)
    end

    # Returns service flags for backend instrumentation
    sig { returns(T::Array[String]) }
    def group_backfill_service_flags
      flags = []

      if @content_scanning.enabled?
        flags << ServiceFlags::CONTENT_BACKFILL_SCAN
      end

      if @wiki_scanning.enabled?
        flags << ServiceFlags::WIKI_INCREMENTAL_SCANS
        flags << ServiceFlags::WIKI_BACKFILL_SCANS
      end

      flags
    end
  end
end
