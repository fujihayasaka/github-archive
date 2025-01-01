# typed: false
# frozen_string_literal: true

module CommitsHelper
  def committers
    return @committers if @committers
    emails = @commits.map { |c| [c.committer_email, c.author_email] }

    @committers = User::CommittersByEmail.find(emails)
  end

  def commit_message(commit)
    message = if commit.message.respond_to? :encode
      commit.message.encode("UTF-8")
    else
      commit.message
    end
    h message
  end

  # Public: Returns the highest number of authors/committers for any single
  # commit, giving up and returning `max` if more than that size is encountered
  # in any commit.  Clamps its return value in the range (min...max)
  #
  # Returns a positive integer value.
  def calculate_max_avatar_count(commits, min:, max:)
    return min if commits.blank?
    max_seen = min
    commits.each do |commit|
      contributors = commit.author_emails
      contributors |= [commit.committer_email] unless commit.committed_via_web?
      contributor_count = contributors.size
      max_seen = contributor_count if contributor_count > max_seen
      return max if max_seen >= max
    end
    max_seen
  end

  def grouped_commits(commits)
    zone = current_user&.time_zone || Time.zone
    commits.group_by do |commit|
      commit.committed_date.in_time_zone(zone).to_date
    end.sort
  end

  # Public: determine the appropriate sizing class depending on the maximum
  # number of authors and committers amoung all commits in the list.  This is
  # optimized to work with a plain array of Commit objects.
  def avatar_count_class(commits)
    max_avatar_count = calculate_max_avatar_count(commits, min: 1, max: 3)
    "authors-#{max_avatar_count}" if max_avatar_count > 1
  end

  def diffstat(commit)
    diffstat = ""
    if commit.diff.available?
      commit.diff.entries.each do |diff|
        status = "m"
        status = "-" if diff.deleted?
        status = "+" if diff.added?
        diffstat << "#{status} #{diff.path}\n"
      end
    end
    diffstat
  end
end
