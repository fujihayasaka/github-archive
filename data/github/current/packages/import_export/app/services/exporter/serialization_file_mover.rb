# typed: strict
# frozen_string_literal: true

module Exporter
  # Service for moving serialization batch files from model type directories to a target location
  # with sequential numbering.
  #
  # This service:
  # 1. Reads all files from multiple model type directories
  # 2. Creates a separate move queue for each model type with sequential numbering
  # 3. Combines all queues into one giant queue for processing
  # 4. Renames files with the pattern: {model_type}_{sequence}.{ext}
  # 5. Moves files to the target directory
  #
  # Input directory structure (from DirectoryPreparer):
  #   {source_dir}/
  #     {model_type_snake_case}/
  #       {batch_id}_{original_filename}
  #
  # Output naming convention:
  #   {model_type}_{000001}.{ext}
  #   {model_type}_{000002}.{ext}
  #
  # Example usage:
  #   mover = Exporter::SerializationFileMover.new(
  #     source_dir: "/tmp/export-work",
  #     target_dir: "/tmp/export-final",
  #     model_types: ["Repository", "PullRequest", "Issue"]
  #   )
  #   result = mover.move_files
  #   # => { files_moved: 142, moves_by_model_type: { "Repository" => 50, "PullRequest" => 42, "Issue" => 50 } }
  class SerializationFileMover
    THREAD_COUNT = 3

    sig { params(source_dir: Pathname, target_dir: Pathname, model_types: T::Array[String]).void }
    def initialize(source_dir:, target_dir:, model_types:)
      @source_dir = source_dir
      @target_dir = target_dir
      @model_types = model_types
    end

    sig { returns({ files_moved: Integer, moves_by_model_type: T::Hash[String, Integer] }) }
    def move_files
      unless @source_dir.exist?
        GitHub.logger.warn(
          "SerializationFileMover: Source directory does not exist",
          source_dir: @source_dir.to_s
        )
        return { files_moved: 0, moves_by_model_type: {} }
      end

      @target_dir.mkpath unless @target_dir.exist?

      # Parallel build per-model-type queues
      model_type_queues = Parallel.map(@model_types, in_threads: THREAD_COUNT) do |model_type|
        build_model_type_move_queue(model_type)
      end

      # Flatten into a single array of move tasks: [source_path, target_path, model_type]
      move_tasks = model_type_queues.flatten(1)

      if move_tasks.empty?
        GitHub.logger.info(
          "SerializationFileMover: No files to move",
          source_dir: @source_dir.to_s
        )
        return { files_moved: 0, moves_by_model_type: {} }
      end

      GitHub.logger.info(
        "SerializationFileMover: Starting to move files",
        source_dir: @source_dir.to_s,
        target_dir: @target_dir.to_s,
        total_files: move_tasks.size
      )

      results = Parallel.map(move_tasks, in_threads: THREAD_COUNT) do |source_path, target_path, model_type|
        begin
          FileUtils.mv(source_path, target_path)
          [:success, model_type]
        rescue StandardError => e
          GitHub.logger.error(
            "SerializationFileMover: Failed to move file",
            source: source_path.to_s,
            target: target_path.to_s,
            error: e.message
          )
          [:failed, model_type]
        end
      end

      # Aggregate results
      moves_by_model_type = Hash.new(0)
      files_moved = 0

      results.each do |status, model_type|
        next if status == :failed

        files_moved += 1
        moves_by_model_type[model_type] += 1
      end

      GitHub.logger.info(
        "SerializationFileMover: Completed moving files",
        files_moved: files_moved,
        moves_by_model_type: moves_by_model_type
      )

      { files_moved: files_moved, moves_by_model_type: moves_by_model_type }
    end

    private

    # Build move queue for a single model type
    sig { params(model_type: String).returns(T::Array[[Pathname, Pathname, String]]) }
    def build_model_type_move_queue(model_type)
      model_type_dir = @source_dir.join(model_type.underscore)
      return [] unless model_type_dir.exist?

      source_files = model_type_dir.children.select(&:file?).sort
      pluralized_type = model_type.underscore.pluralize

      source_files.each.with_index(1).map do |source_file, index|
        sequence = index.to_s.rjust(6, "0")
        target_filename = "#{pluralized_type}_#{sequence}#{source_file.extname}"
        target_path = @target_dir.join(target_filename)
        [source_file, target_path, model_type]
      end
    end
  end
end
