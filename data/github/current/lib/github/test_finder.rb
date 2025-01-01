# typed: true
# frozen_string_literal: true

require_relative "./test_finder/git_change_finder"
require_relative "./test_finder/source_file_mapper"
require_relative "./test_finder/test_oracle_mapper"

module GitHub
  module TestFinder
    extend T::Sig

    class TestCollection < T::Struct
      prop :low_impact_tests, T::Array[String]
      prop :high_impact_tests, T::Array[String]
      prop :changed_files_with_low_impact, T::Hash[String, Integer]
      prop :changed_files_with_high_impact, T::Hash[String, Integer]
    end

    MAX_PR_FILES_TO_SEARCH = 100
    MAX_IMPACT_TO_RUN = 75

    sig { params(merge_base_ref: T.nilable(String), pr_sha: T.nilable(String)).returns(T::Array[String]) }
    def self.related_tests_regexp(merge_base_ref:, pr_sha:)
      changed_files = find_changed_files(merge_base_ref:, pr_sha:)
      source_file_mapper = SourceFileMapper.new

      changed_file_to_test_files = changed_files.to_h do |changed_file|
        [
          changed_file,
          source_file_mapper.test_path_for(changed_file)
        ]
      end

      existing_files = changed_file_to_test_files.values.select do |test_file|
        test_file && Rails.root.join(test_file).exist?
      end.uniq

      if !existing_files.empty?
        TestOracle.log "[engine: regexp] Changed files and the related test file:"
        changed_file_to_test_files.each do |changed_path, test_path|
          TestOracle.log "[engine: regexp]   #{changed_path} => #{test_path}" if existing_files.include?(test_path)
        end
      end
      existing_files
    end

    sig do params(
      merge_base_ref: T.nilable(String),
      pr_sha: T.nilable(String),
      covmap_file: Pathname,
      sharded_covmap_path: Pathname,
      metric_tags: T::Array[String]).returns(TestCollection)
    end
    def self.related_tests_covmap(
      merge_base_ref:,
      pr_sha:,
      covmap_file:,
      sharded_covmap_path:,
      metric_tags: []
    )
      changed_files = find_changed_files(merge_base_ref:, pr_sha:)

      if changed_files.length > MAX_PR_FILES_TO_SEARCH
        TestOracle.log "  WARNING: more than the maximum number of impacted files have been detected!"
        TestOracle.log "  Results are likely incomplete."
      end

      mapper = TestOracleMapper.new(covmap_file, sharded_covmap_path)

      impact = mapper.impact_for(changed_files)
      TestOracle.log "Detected impact (affected test files) for changed files:"
      impact.each do |changed_file, impact|
        TestOracle.log "  (#{impact}) #{changed_file}"
      end
      changed_files_with_low_impact = impact.select { |_k, v| v < MAX_IMPACT_TO_RUN }
      changed_files_with_high_impact = impact.select { |_k, v| v >= MAX_IMPACT_TO_RUN }

      TestOracle.metrics_count("high_impact", changed_files_with_high_impact.size, metric_tags) if changed_files_with_high_impact.any?

      changed_file_to_test_files = changed_files_with_low_impact.keys.to_h do |changed_file|
        [
          changed_file,
          mapper.test_paths_for(changed_file)
        ]
      end

      high_impact_changed_file_to_test_files = (changed_files_with_high_impact.keys - changed_files_with_low_impact.keys).to_h do |changed_file, _|
        [
          changed_file,
          mapper.test_paths_for(changed_file)
        ]
      end

      TestOracle.log "[engine: covmap] Changed files and the related test file:"
      changed_file_to_test_files.each do |changed_path, test_path|
        TestOracle.log "[engine: covmap]   #{changed_path} => #{test_path}"
      end

      tests = changed_file_to_test_files.values.flatten.select do |test_file|
        !test_file.nil? && Rails.root.join(test_file).exist?
      end.uniq

      high_impact_tests = high_impact_changed_file_to_test_files.values.flatten.select do |test_file|
        !test_file.nil? && Rails.root.join(test_file).exist?
      end.uniq

      TestCollection.new(low_impact_tests: tests,
                         high_impact_tests: high_impact_tests,
                         changed_files_with_low_impact: changed_files_with_low_impact,
                         changed_files_with_high_impact: changed_files_with_high_impact
                        )
    end

    sig { params(merge_base_ref: T.nilable(String), pr_sha: T.nilable(String)).returns(T::Array[String]) }
    def self.changed_files_for(merge_base_ref:, pr_sha:)
      hash_key = "#{merge_base_ref}+#{pr_sha}"
      @changed_files[hash_key] ||= find_changed_files(merge_base_ref:, pr_sha:)
    end

    sig { params(merge_base_ref: T.nilable(String), pr_sha: T.nilable(String)).returns(T::Array[String]) }
    def self.find_changed_files(merge_base_ref:, pr_sha:)
      @changed_files ||= {}

      # memoize the changed files, to avoid multiple API calls for same pr_sha
      hash_key = "#{merge_base_ref}+#{pr_sha}"

      # Not enabled since it gave inaccurate results with the _test.rb short circuit
      # return @changed_files[hash_key] if @changed_files[hash_key]

      changed_files = if pr_sha.nil?
        GitChangeFinder.all(merge_base_ref: merge_base_ref || "origin/master", force_since_merge_base: !!merge_base_ref)
      else
        find_changed_files_from_pr(pr_sha)
      end

      @changed_files[hash_key] = changed_files

      changed_files
    end

    def self.find_changed_files_from_pr(pr_sha)
      sha_id = if pr_sha == "" || pr_sha == "from_pr"
        stdout, _status = Open3.capture2("git rev-parse HEAD")
        stdout.strip
      else
        pr_sha
      end

      script = File.join(Rails.root, "script", "find-pr-files-for-ci")
      states = "added,removed,modified,renamed,copied,changed"
      command = Shellwords.join([script, sha_id, "-s", states, "-m", (MAX_PR_FILES_TO_SEARCH + 1).to_s])

      TestOracle.log "Looking up files via PR for sha: #{sha_id}, executing: #{command}"

      result, status = Open3.capture2(command)
      files = result.lines.map(&:strip).reject(&:empty?)

      TestOracle.log "Exit status: #{status.exitstatus.inspect}"
      TestOracle.log "Found changed files from PR:"
      files.each { |f| TestOracle.log " - #{f}" }

      return [] unless status.exitstatus&.zero?
      files
    end
  end
end
