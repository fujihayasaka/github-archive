# typed: true
# frozen_string_literal: true

class ScopedIntegrationInstallation
  # This class allows checking feature flags on repositories
  # without instantiating a Repository.
  class RepositoryFlipperActor
    include GitHub::VexiActor

    def initialize(id)
      @id = id
    end

    def vexi_id
      "Repository:#{@id}"
    end
  end
end
