# typed: true
# frozen_string_literal: true

class PreReceiveEnvironmentDeleteJob < ApplicationJob
  queue_as :pre_receive_environment_delete

  class DeleteException < Exception; end

  def perform(env_id, sha = nil)
    update_script = if Rails.env.production? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      "/usr/local/share/enterprise/ghe-hook-env-cleanup"
    else
      "#{Rails.root}/script/ghe-hook-env-cleanup"
    end
    if sha.nil?
      run([update_script, env_id, "-a"])
    else
      run([update_script, env_id, sha])
    end
  end

  def run(command)
    process = Progeny::Command.new(*(command))

    if !process.status.success?
      Failbot.push(
        command: command.inspect,
        stdout: process.out,
        stderr: process.err,
        status: process.status.exitstatus.inspect,
      )
      raise DeleteException, process.out
    else
      process.out.chomp
    end
  end
end
