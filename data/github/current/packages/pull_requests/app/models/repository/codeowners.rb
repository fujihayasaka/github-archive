# typed: true
# frozen_string_literal: true

require "codeowners"

class Repository
  # Represents the OWNERS file in a repository. Owners are responsible for
  # reviewing pull requests that change files in directories they own. An
  # owner's review can be required before merging into a protected branch
  # is allowed.
  class Codeowners
    FILE_SIZE_LIMIT = 3.megabytes
    PARSER_CLASS = ::Codeowners::MultibyteParser
    include Enumerable
    include ActionView::Helpers::NumberHelper

    attr_reader :repository, :ref, :file
    attr_accessor :paths

    delegate :errors, :owner_errors, to: :file
    delegate :rules_by_owner, :owners_by_rule, :owners_for_path, to: :result_from_file

    def initialize(repository, ref: nil, paths: [])
      start_time = GitHub::Dogstats.monotonic_time
      @repository = repository
      @ref = ref || repository.default_branch
      @paths = paths
      @owner_resolver = Codeowners::ActiveRecordOwnerResolver.new(repository)

      # If CODEOWNERS file does not exist do not make unnecessary requests

      # `repository#codeowners` checks if the CODEOWNERS file exists at the default branch only
      # This check is saving unnecessary requests when `@ref` is the default branch and there is no CODEOWNERS file there
      # if `@ref` is not the default branch OR there is a CODEOWNERS file at the default branch
      # then we have to do the calls to get it

      return if @ref == repository.default_branch && !repository.codeowners?

      directory = @repository.directory(@ref)

      @tree_entry = PreferredFile.find(
        directory: directory,
        type: :codeowners,
      )

      if @tree_entry
        if @tree_entry.truncated?
          # Fetching the single tree entry will use a higher limit of
          # 3 MB and skip truncation, see TreeListable::DEFAULT_LIMITS.
          @tree_entry = repository.tree_entry(
            directory.commit_sha,
            @tree_entry.path,
            limit: FILE_SIZE_LIMIT
          )

          if @tree_entry.data.empty?
            GitHub.logger.info("Codeowners file exceeds file limit", log_context)
          else
            GitHub.logger.info("Codeowners file truncated", log_context)
          end
        end
        file_content = @tree_entry.data.to_s
        @file = ::Codeowners::File.new(
          file_content,
          owner_resolver: @owner_resolver,
          parser_class: PARSER_CLASS
        )

        if @file.rules.empty? && @file.errors.any?
          GitHub.logger.info("Codeowners file invalid", log_context.merge("exception.message": errors_string))
        elsif @file.errors.any?
          GitHub.logger.info("Codeowners file contained some errors", log_context.merge("exception.message": errors_string))
        end
      end
    ensure
      record_init_timing(start_time)
    end

    TAGS = { true => ["tree_entry:true"], false => ["tree_entry:false"] }
    def record_init_timing(start_time)
      duration = (GitHub::Dogstats.monotonic_time - start_time) * 1000
      GitHub.dogstats.distribution("codeowners.init", duration, tags: TAGS[!!@tree_entry])
    end

    def path
      @tree_entry && @tree_entry.path
    end

    def exists?
      @tree_entry.present?
    end

    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def tree_oid
      @tree_oid ||= repository.refs.find(ref)&.target_oid
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    def each(&block)
      owners.each(&block)
    end

    def include?(owner)
      rules_by_owner.key?(owner)
    end

    # Public: Determines which owners are affected by changes to these paths.
    #
    # Returns an Array of Users and Teams.
    def owners
      rules_by_owner.keys
    end

    # Public: Determines which owners are visible to the given viewer.
    #
    # NOTE: Users are always considered visible for the purposes of ownership.
    #       We do not take into account spammy or blocked users as it is
    #       important info for the viewr to have regardless of their state.
    #       Teams are filtered based on their visibility settings.
    #
    # Returns an array of Users and Teams that are safe to display to the viewer.
    def async_owners_visible_to(viewer)
      async_teams_visible_to(viewer).then do |visible_teams|
        owners.select do |user_or_team|
          next true if user_or_team.is_a?(User)
          visible_teams.include?(user_or_team)
        end
      end
    end

    def owners_visible_to(viewer)
      async_owners_visible_to(viewer).sync
    end

    def users
      owners.select { |owner| owner.is_a?(User) }
    end

    def teams
      owners.select { |owner| owner.is_a?(Team) }
    end

    def async_teams_visible_to(viewer)
      promises = teams.map { |t| t.async_visible_to?(viewer) }
      Promise.all(promises).then do |results|
        results_by_team = Hash[teams.zip(results)]
        results_by_team.select { |_, visible| visible }.keys
      end
    end

    def teams_visible_to(viewer)
      async_teams_visible_to(viewer).sync
    end

    # Public: Return the paths that are owned by the given owner, including
    #         any teams they are a member of if the given owner is a User.
    #
    # owner - A User or Team.
    #
    # Returns an Array of file path Strings.
    def paths_for_owner(owner)
      return [] unless owner

      @paths_for_owner ||= {}
      @paths_for_owner[owner] ||= begin
        owner_identifier = if owner.is_a?(Team)
          owner.name_with_owner
        else
          owner.display_login
        end

        result = result_from_file
        owner_paths = Set.new
        owner_paths.merge(result.paths_for_owner("@#{owner_identifier}"))
        owner_paths.merge(paths_for_user_from_teams(owner))
        owner_paths.to_a
      end
    end

    def owned_by?(owner:, path:)
      paths_for_owner(owner).include?(path)
    end

    def rule_for_path(path)
      result_from_file.rules_by_path[path]
    end

    private

    def log_context
      {
        "code.namespace": self.class.name,
        "gh.repo.id": repository.id,
        "gh.pull_request.codeowners.file_size": @tree_entry.size,
      }
    end

    def errors_string
      file.errors
        .map { |err| "#{err.kind} on line #{err.line} (#{err.source.strip})" }
        .to_sentence
    end

    def result_from_file
      return @result_from_file if defined?(@result_from_file)
      return @result_from_file = build_empty_result unless file && repository.plan_supports?(:codeowners)

      if use_graph_matcher?
        matcher_class = ::Codeowners::Matcher::RuleGraph
        matcher_tag = "matcher:graph"
      else
        matcher_class = ::Codeowners::Matcher::PathTree
        matcher_tag = "matcher:tree"
      end

      @result_from_file = begin
          track_loading_owners(matcher_tag) do
            file.match(paths, matcher: matcher_class)
          end
        rescue RegexpError
          # One of the rules resulted in an invalid Regexp, ignore the whole file
          build_empty_result
        end
    end

    def build_empty_result
      ::Codeowners::Matcher::Result.new(@owner_resolver)
    end

    def use_graph_matcher?
      paths.count >= 250 && file.rules.count >= 8000
    end

    def track_loading_owners(*tags, &block)
      path_bucket = bucket_tag(
        paths.count,
        "num_paths",
        boundaries: [0, 3, 10, 50, 250, 3000],
      )
      rules_bucket = bucket_tag(
        file.rules.count,
        "num_rules",
        boundaries: [0, 5, 50, 600, 3500, 8000],
      )

      GitHub.dogstats.distribution_time(
        "codeowners.owners_from_file.timing",
        tags: tags + [path_bucket, rules_bucket],
        &block
      )
    end

    def bucket_tag(count, prefix, boundaries:)
      sorted_boundaries = boundaries.sort

      sorted_boundaries.each_cons(2) do |min, max|
        if count >= min && count < max
          return "#{prefix}:#{min}-#{max}"
        end
      end

      "#{prefix}:#{sorted_boundaries.last}-up"
    end

    def paths_for_user_from_teams(user)
      return [] unless user.present?
      return [] if user.is_a?(Team)

      user_team_ids = user.team_ids(with_ancestors: true)
      return [] unless user_team_ids.any?

      paths.select do |path|
        owners = rule_for_path(path)&.owners || []

        owners.select(&:teamname?).any? do |owner|
          team = @owner_resolver.resolve(owner.identifier)
          user_team_ids.include?(team&.id)
        end
      end
    end
  end
end
