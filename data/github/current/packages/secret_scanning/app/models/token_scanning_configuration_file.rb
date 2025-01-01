# typed: strict
# frozen_string_literal: true

class TokenScanningConfigurationFile
  extend T::Sig

  include GitHub::Memoizer

  DEFAULT_NAME = "secret_scanning.yml"
  DEFAULT_NAME_PATH = T.let(".github/" + DEFAULT_NAME, String)
  MAX_FILE_SIZE = 1048576 # 1MB limit on file size
  MAX_NUMBER_OF_PATTERNS = 1000

  sig { params(tree_entry: TreeEntry).void }
  def initialize(tree_entry)
    @tree_entry = T.let(tree_entry, T.nilable(TreeEntry)) unless tree_entry.size > MAX_FILE_SIZE
    record_instantiation_stats
  end

  sig { returns(T.nilable(String)) }
  def name
    @tree_entry&.name
  end

  sig { params(path: String).returns(T::Boolean) }
  def ignore_path?(path)
    begin
      ignore = T.let(false, T::Boolean)
      patterns = omitted_paths
      if patterns && (defined? patterns.each) && (defined? patterns.slice)
        patterns.first(MAX_NUMBER_OF_PATTERNS).each do |pattern| # read up to MAX_NUMBER_OF_PATTERNS patterns
          if File.fnmatch?(pattern, path, File::FNM_CASEFOLD)
            ignore = true
            break
          end
        end
      end
      ignore
    rescue Psych::SyntaxError => e
      GitHub.dogstats.increment("token_scan_config_syntax_error")
      false
    end
  end

  sig { returns(T.nilable(T.any(String, T::Array[T.untyped]))) }
  def omitted_paths
    yaml ? yaml["paths-ignore"] : []
  end

  private

  sig { void }
  def record_instantiation_stats
    GitHub.dogstats.increment("token_scan_config_instantiated")
  end

  sig { returns(T.untyped) }
  memoize def yaml
    @tree_entry ? YAML.safe_load(@tree_entry.data) : nil
  end
end
