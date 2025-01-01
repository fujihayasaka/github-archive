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

  def grouped_commits(commits)
    zone = current_user&.time_zone || Time.zone
    commits.group_by do |commit|
      commit.committed_date.in_time_zone(zone).to_date
    end.sort
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
