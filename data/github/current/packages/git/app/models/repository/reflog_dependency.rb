# typed: true
# frozen_string_literal: true

module Repository::ReflogDependency
  extend T::Helpers

  requires_ancestor { Repository }

  # RefLog entries for this repository.
  #
  # ref     - Specific ref to fetch reflog entries for (defaults to nil for
  #           all refs.)
  # options - Optional Hash.
  #           :limit - Fetch only the most recent limit entries (default: 50)
  #           :page  - Page for which to return paginated entries
  #
  # Returns a reverse chronologically sorted Array of LoggedPush objects.
  def reflog(ref = nil, options = nil)
    options ||= {}
    options[:limit] ||= 50

    pushlog_opts = {}
    [:ref, :limit, :squash, :before_oid, :after_oid, :newer_than, :older_than].each do |opt|
      pushlog_opts[opt] = options[opt] if options[opt]
    end
    pushlog_opts[:ref] = ref if ref
    pushlog_opts[:pagination] = true

    entries = rpc.push_log(pushlog_opts)
    prev_page = next_page = T.let(false, T::Boolean)
    LoggedPush.preload_associations(
      entries.inject([]) do |pushes, line|
        if line =~ /\A# \d+ newer entries available/
          prev_page = true
        elsif line =~ /\A# \d+ older entries available/
          next_page = true
        elsif line.start_with?("  ")
          pushes.last.add_target(line)
        else
          pushes << LoggedPush.parse_reflog_line(line)
        end

        pushes
      end,
    )
  end
end
