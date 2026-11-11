# typed: true
# frozen_string_literal: true

# Called by `VerifyCreationMetadataOnPushTest` for each codespace that could be impacted by the push. Specifically
# we are checking if the codespace's OID is no longer valid and fixing it and any possible devcontainer references
# if it is.
module Codespaces
  class VerifyCreationMetadata < Command
    module SafeDevContainer
      refine Codespaces::DevContainer do
        def exists?
          super
        rescue Codespaces::DevContainer::ReadError
          false
        end
      end
    end

    using SafeDevContainer

    attr_reader :codespace, :force_pushed

    def initialize(codespace:, force_pushed:)
      @codespace = codespace
      @force_pushed = force_pushed
    end

    def perform
      published_from_template = codespace.from_codespace_template? && codespace.published?
      # Require either the push to have been a force push or for the codespace to have been published from a template
      return unless published_from_template || force_pushed

      if !codespace.repository.commits.exist?(codespace.oid) && new_codespace_oid
        # Our original OID is no longer valid and we found a new OID, so we need to update it
        codespace.oid = new_codespace_oid
        if !codespace.devcontainer_path || !codespace.dev_container.exists?
          # If we don't have a devcontainer at all or it's no longer valid then try using the default devcontainer path.
          # This may reset it back to nil if we can no longer find a devcontainer in the repository at this new OID.
          codespace.devcontainer_path = Codespaces::DevContainer.get_default_path(codespace.repository, new_codespace_oid)
        end
        codespace.save
      end
    end

    private

    def new_codespace_oid
      return @new_codespace_oid if defined?(@new_codespace_oid)

      @new_codespace_oid = Codespaces::GetTargetRef.new(repository: codespace.repository, name_or_oid: codespace.ref).call&.target_oid
    end
  end
end
