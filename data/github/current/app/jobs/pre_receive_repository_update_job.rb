# typed: true
# frozen_string_literal: true

# Enqueued after a new hook is configured with a given repository
# or the given repository receives a push and we need to update the
# bits on disk for pre-receive hooks.
#
#   repository_id - The id if the repository containing pre-receive scripts
#   url           - URL of where to retrieve this repository (internal URL)
#
class PreReceiveRepositoryUpdateJob < ApplicationJob
  queue_as :pre_receive_repository_update

  class Error < StandardError; end

  def perform(repository_id, url)
    repository = Repositories.domain.by_id(repository_id)

    Failbot.push(
      job: self.class.name,
      repo: T.cast(repository, T.nilable(Repository))&.readonly_name_with_owner, # rubocop:todo GitHub/AvoidCast
      url: url,
    )

    return unless repository

    result = nil
    if Rails.env.development? || Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      hook_repo_dir = File.join(GitHub.custom_hooks_dir, "repos")
      repo_path = File.join(hook_repo_dir, repository_id.to_s)
      if Dir.exist?(repo_path)
        result = Progeny::Command.new("git", "-C", repo_path, "pull")
      else
        FileUtils.mkdir_p(hook_repo_dir)
        result = Progeny::Command.new("git", "clone", url, repo_path)
      end
    else
      result = Progeny::Command.new("/usr/local/share/enterprise/ghe-hook-repo-update", repository_id.to_s, url)
    end

    unless result.status.exitstatus == 0
      raise Error, "There's been a problem updating the repository:
exit status: #{result.status.exitstatus}
stdout: #{result.out}
stderr: #{result.err}"
    end
  end
end
