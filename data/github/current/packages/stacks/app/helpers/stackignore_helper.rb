# typed: true
# frozen_string_literal: true

# Helper class to ignore cloning of files specified in .stackignore file

class StackignoreHelper

  GITHUB_STACKS_IGNORE_FILE_PATH = ".stackignore"
  GITHUB_STACKS_FOLDER_PATH = ".github/stacks"
  README_FILE_PATH = "README.md"
  MAX_IGNORE_RULES_COUNT = 100

  class IgnoreRule
    attr_accessor :pattern, :anchored, :negation, :case_sensitive
    def initialize(pattern, anchored, negation, case_sensitive = true)
      @pattern  = pattern
      @anchored = anchored
      @negation = negation
      @case_sensitive = case_sensitive
    end
  end

  def create_ignore_rules
    @ignore_rules_set = Set.new
    @ignore_rules_set.add(IgnoreRule.new(GITHUB_STACKS_IGNORE_FILE_PATH, true, false))
    @ignore_rules_set.add(IgnoreRule.new(File.join(GITHUB_STACKS_FOLDER_PATH, "**"), true, false))
    @ignore_rules_set.add(IgnoreRule.new(README_FILE_PATH, true, false, false))

    entry = @target_repo.blob(@commit_sha, GITHUB_STACKS_IGNORE_FILE_PATH)
    return unless entry && entry.data

    unparsed_ignore_rules = []

    # parse .stackignore file and ignore comments
    unparsed_ignore_rules += entry.data.split(/\r?\n/).reject { |f| f =~ /\A(#.*|\s*)\z/ }

    if unparsed_ignore_rules.count > MAX_IGNORE_RULES_COUNT
      raise Errors::CloneError.new("Number of ignore rules in .stackignore more than allowed")
    end

    unparsed_ignore_rules.each do |rule|
      # anchored rules: starts with /
      anchored = !!(rule =~ /\//) && (rule.index("/") != (rule.length - 1))

      # directory rules: ends with /
      directory = !!(rule =~ /\/$/)

      # negation rules: starts with !
      negation = !!(rule =~ /^!/)

      # extract the pattern
      pattern = rule.sub(/^!/, "")
      pattern = pattern.sub(/^\//, "")
      pattern = pattern.sub(/\/$/, "")

      if anchored
        @ignore_rules_set.add(IgnoreRule.new(File.join(pattern, "*"), anchored, negation))
        if directory
          @ignore_rules_set.add(IgnoreRule.new(File.join(pattern, "*"), anchored, negation))
          @ignore_rules_set.add(IgnoreRule.new(File.join(pattern, "**/*"), anchored, negation))
        end
      else
        new_pattern = File.join("**", pattern)
        @ignore_rules_set.add(IgnoreRule.new(new_pattern, anchored, negation))
        if directory
          @ignore_rules_set.add(IgnoreRule.new(File.join(new_pattern, "*"), anchored, negation))
          @ignore_rules_set.add(IgnoreRule.new(File.join(new_pattern, "**/*"), anchored, negation))
        end
      end
      @ignore_rules_set.add(IgnoreRule.new(pattern, anchored, negation))
    end
  end

  def remove_ignored_files(target_repo, commit_sha)
    @target_repo = target_repo
    @commit_sha = commit_sha

    # create ignore rules
    create_ignore_rules

    tree_oid, tree_entries, truncated = @target_repo.tree_entries(@commit_sha, "",
      recursive: true, limit: RepositoryClone::MAX_TEMPLATE_FILE_LIMIT, skip_size: false)

    new_tree = Hash.new
    tree_entries.map do |entry|
      if entry.type == "blob" && should_ignore(entry.path)
        new_tree[entry.path] = nil
      end
    end

    new_tree_sha = begin
      @target_repo.rpc.create_tree(new_tree, tree_oid)
    rescue => e # rubocop:todo Lint/GenericRescue
      raise Errors::CloneError.new("Error while new creating new tree after removing .github/stacks folder => #{e.message}")
    end

    new_tree_sha
  end

  def should_ignore(path)
    @ignore_rules_set.any? do |rule|
      flags = rule.anchored ? 0 : File::FNM_PATHNAME
      flags = rule.case_sensitive ? flags : flags | File::FNM_CASEFOLD
      if File.fnmatch(rule.pattern, path, flags)
        return true
      end
    end
    false
  end
end
