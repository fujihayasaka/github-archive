# typed: strict
# frozen_string_literal: true

module ImportExport
  class Domain < GH::Domain::Base
    # Repository import has started.
    sig { params(repository: Repository).void }
    def importing_started!(repository)
      ImportExportConfig.new(repository).enable_is_importing(actor: repository.owner)
    end

    # Repository import has finished.
    sig { params(repository: Repository).void }
    def importing_stopped!(repository)
      ImportExportConfig.new(repository).disable_is_importing(actor: repository.owner)
    end

    # Whether the repository is importing.
    sig { params(repository: Repository).returns(T::Boolean) }
    def is_importing?(repository)
      ImportExportConfig.new(repository).is_importing_enabled?
    end
  end
end
