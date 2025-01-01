# frozen_string_literal: true

# Adapted from:
# https://github.com/github/github/blob/master/lib/github/stack_filter.rb

# Used by GitHub::SQLCheckers::SchemaDomain::QuerySubscriber.
#
# Replicates the functionality of Rollup.first_significant_frame in isolation
# because other instrumentation relies on the contents of Rollup's path denylist.
module DependencyGraph::SqlUtils
  class StackFilter
    DENYLIST = [
      "THE WIRE",
      "config/initializers/",
      "vendor/",
      "lib/instrumentor.rb",
      "lib/dependency_graph/sql_utils/",
      ".rbenv/"
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
end
