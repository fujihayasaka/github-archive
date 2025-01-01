# typed: true
# frozen_string_literal: true

class ScopedIntegrationInstallation
  # This class allows checking feature flags on repositories
  # without instantiating a Repository.
  class RepositoryFlipperActor
    include GitHub::FlipperActor
    include GitHub::VexiActor

    def initialize(id)
      @id = id
    end

    def flipper_id
      "Repository:#{@id}"
    end

    def vexi_id
      flipper_id
    end
  end
end
