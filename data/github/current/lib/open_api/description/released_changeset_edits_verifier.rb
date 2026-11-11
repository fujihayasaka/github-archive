# typed: true
# frozen_string_literal: true

require "open3"
require "pathname"
require "shellwords"

module OpenApi
  module Description
    class ReleasedChangesetEditsVerifier
      class Result
        attr_reader :violations

        def initialize(violations:)
          @violations = violations
        end

        def valid?
          violations.empty?
        end
      end

      class Change
        attr_reader :status, :path, :previous_path

        def initialize(status:, path:, previous_path: nil)
          @status = status
          @path = path
          @previous_path = previous_path
        end
      end

      ALLOWED_EDITABLE_KEYS = %w[description notes].freeze
      CHANGESETS_PATHSPEC = "app/api/description/changesets/*.yaml"
      DEFAULT_BASE_REF = "origin/master"

      def initialize(base_ref: nil, repo_root: GitHub::AppEnvironment.root)
        @base_ref = base_ref
        @repo_root = Pathname.new(repo_root)
      end

      def verify
        base_ref = resolve_base_ref
        violations = changed_changesets(base_ref).flat_map do |change|
          violations_for_change(change, base_ref)
        end

        Result.new(violations: violations)
      end

      private

      def resolve_base_ref
        candidates = [@base_ref, ENV["GITHUB_BASE_SHA"], ENV["BASE_REF"], ENV["GITHUB_BASE_REF"], DEFAULT_BASE_REF].compact

        candidates.each do |candidate|
          return candidate if git_ref_exists?(candidate)

          origin_candidate = "origin/#{candidate}"
          return origin_candidate if !candidate.start_with?("origin/") && git_ref_exists?(origin_candidate)
        end

        raise ArgumentError, "Could not resolve a base ref for released changeset verification"
      end

      def git_ref_exists?(ref)
        _, status = Open3.capture2e("git", "rev-parse", "--verify", "-q", ref, chdir: @repo_root.to_s)
        status.success?
      end

      def changed_changesets(merge_base)
        output = run_git!("diff", "--name-status", merge_base, "HEAD", "--", CHANGESETS_PATHSPEC)

        output.lines.filter_map do |line|
          fields = line.strip.split("\t")
          next if fields.empty?

          status = fields.shift
          if status.start_with?("R", "C")
            Change.new(status: status, previous_path: fields[0], path: fields[1])
          else
            Change.new(status: status, path: fields[0])
          end
        end
      end

      def violations_for_change(change, merge_base)
        case change.status[0]
        when "A"
          []
        when "D"
          deleted_changeset_violations(change.path, merge_base)
        when "R", "C"
          renamed_changeset_violations(change, merge_base)
        else
          modified_changeset_violations(change.path, merge_base)
        end
      rescue StandardError => error
        ["#{change.path} could not be verified: #{error.message}"]
      end

      def deleted_changeset_violations(path, merge_base)
        base_changeset = load_changeset_from_ref(merge_base, path)
        return [] unless released_changeset?(base_changeset)

        ["#{path} is a released changeset and cannot be deleted"]
      end

      def renamed_changeset_violations(change, merge_base)
        base_changeset = load_changeset_from_ref(merge_base, change.previous_path)
        return [] unless released_changeset?(base_changeset)

        ["#{change.previous_path} is a released changeset and cannot be renamed"]
      end

      def modified_changeset_violations(path, merge_base)
        base_changeset = load_changeset_from_ref(merge_base, path)
        return [] unless released_changeset?(base_changeset)

        current_changeset = load_current_changeset(path)
        changed_keys = changed_keys(base_changeset.raw, current_changeset.raw)
        disallowed_keys = changed_keys - ALLOWED_EDITABLE_KEYS
        return [] if disallowed_keys.empty?

        [
          "#{path} modifies released changeset fields: #{disallowed_keys.sort.join(", ")}. Only description and notes may be edited after release."
        ]
      end

      def changed_keys(base_raw, current_raw)
        (base_raw.keys | current_raw.keys).select { |key| base_raw[key] != current_raw[key] }
      end

      def released_changeset?(changeset)
        changeset.version != :next
      end

      def load_changeset_from_ref(ref, path)
        load_changeset(run_git!("show", "#{ref}:#{path}"), path)
      end

      def load_current_changeset(path)
        load_changeset(@repo_root.join(path).read, path)
      end

      def load_changeset(content, path)
        OpenApi::Description::Changeset.new(YAML.safe_load(content), Pathname.new(path).basename)
      end

      def run_git!(*args)
        command = Shellwords.join(["git", *args])
        output, status = Open3.capture2e(command, chdir: @repo_root.to_s)
        return output if status.success?

        raise ArgumentError, output.strip.presence || "git #{args.join(' ')} failed"
      end
    end
  end
end
