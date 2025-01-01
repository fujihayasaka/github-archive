# typed: true
# frozen_string_literal: true

# Used by GitHub::SQLCheckers::SchemaDomain::QuerySubscriber.
#
# Replicates the functionality of Rollup.first_significant_frame in isolation
# because other instrumentation relies on the contents of Rollup's path denylist.
class GitHub::StackFilter
  DENYLIST = [
    "THE WIRE",
    "bin/ernicorn",
    "config/ernicorn.rb",
    "packages/git/app/models/git/ref.rb",
    "packages/git/app/models/repository/commits_dependency.rb",
    "packages/git/app/models/repository/refs_dependency.rb",
    "config/instrumentation",
    "config/subscribers",
    "lib/github/notifications",
    "lib/github/active_record_enumerable_protection.rb",
    "lib/github/association_instrumenter.rb",
    "lib/github/cache",
    "lib/github/config/mysql.rb",
    "lib/github/config/notifications.rb",
    "lib/github/experiment.rb",
    "lib/github/request_timer.rb",
    "lib/github/sql/batched.rb",
    "lib/github/sql/batched_between.rb",
    "vendor/",
    "lib/github/config/stats.rb",
    "lib/github/sql_checkers/schema_domain/statement_checker.rb",
    "lib/github/sql_checkers/table_sharding/statement_checker.rb",
    "lib/github/memory_dogstats_d.rb",
  ]

  # Find the first significant frame in a backtrace
  #
  # If there is no such frame, the first frame is used.
  #
  # backtrace - Enumerable that yields String backtrace lines (e.g.,
  #             Kernel#caller or Exception#backtrace)
  #
  # Returns a String from the backtrace
  def self.first_significant_frame(backtrace)
    return "" if backtrace.blank?

    significant_frame = backtrace.detect { |frame| significant?(frame) }

    significant_frame || backtrace.first || ""
  end

  # Determine whether a frame is "significant"
  #
  # "Significant" frames are ones that don't match the denylist.
  #
  # frame - String backtrace line (e.g., from Kernel#caller or
  #         Exception#backtrace)
  #
  # Returns a Boolean
  def self.significant?(frame)
    DENYLIST.none? { |exclusion| frame.include?(exclusion) }
  end

  # Canonicalize a frame string to relative path and line number.
  #
  # E.g., turns:
  #
  #     /Users/octocat/github/github/app/models/repository.rb:2156:in `ensure_uniqueness_of_name'
  #
  # into:
  #
  #     app/models/repository.rb:2156
  #
  # frame - String backtrace line (e.g., from Kernel#caller or
  #         Exception#backtrace)
  #
  # Returns a String
  def self.path_with_linenumber(frame)
    frame.delete_prefix("#{Rails.root}/").split(":", 3).first(2).join(":")
  end
end
