# typed: true
# frozen_string_literal: true

module TrustMetadata
  class AttestationAuthorizer
    attr_reader :actor
    def initialize(actor)
      @actor = actor
    end

    def can_read_repo?(repo)
      async_can_read_repo?(repo).sync
    end

    def async_can_read_repo?(repo)
      can_read_promises = [repo.resources.contents.async_readable_by?(actor),
                           repo.resources.attestations.async_readable_by?(actor)]

      Promise.all(can_read_promises).then do |read_contents, read_attestations|
        if FeatureFlag.vexi.enabled_or_raise?(:attestations_api_private_beta, repo.owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
          read_contents || read_attestations
        else
          read_attestations
        end
      end
    end

    def can_write_repo?(repo)
      async_can_write_repo?(repo).sync
    end

    def async_can_write_repo?(repo)
      can_write_promises = [repo.resources.contents.async_writable_by?(actor),
                            repo.resources.attestations.async_writable_by?(actor)]

      Promise.all(can_write_promises).then do |write_contents, write_attestations|
        if FeatureFlag.vexi.enabled_or_raise?(:attestations_api_private_beta, repo.owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
          write_contents || write_attestations
        else
          write_attestations
        end
      end
    end
  end
end
