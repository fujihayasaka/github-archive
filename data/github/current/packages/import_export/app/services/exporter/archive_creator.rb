# typed: strict
# frozen_string_literal: true

module Exporter
  class ArchiveCreator
    include GitHub::Migrator::TarUtils

    sig { params(working_dir: String, archive_path: String).void }
    def initialize(working_dir:, archive_path:)
      @working_dir = working_dir
      @archive_path = archive_path
    end

    sig { returns(String) }
    def create
      create_archive(@working_dir, @archive_path)
      @archive_path
    end
  end
end
