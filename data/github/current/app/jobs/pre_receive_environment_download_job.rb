# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class PreReceiveEnvironmentDownloadJob < ApplicationJob
  queue_as :pre_receive_environment_download

  class DownloadException < Exception; end

  def self.run(command)
    process = Progeny::Command.new(*(command))

    if !process.status.success?
      Failbot.push(
          command: command.inspect,
          stdout: process.out,
          stderr: process.err,
          status: process.status.exitstatus.inspect,
      )
      raise DownloadException, process.err
    else
      process.out.chomp
    end
  end

  def perform(env_id)
    hook_env = PreReceiveEnvironment.find(env_id)
    update_script = if Rails.env.production? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      "/usr/local/share/enterprise/ghe-hook-env-update"
    else
      "#{Rails.root}/script/ghe-hook-env-update"
    end

    with_write do
      hook_env.start_download
      begin
        checksum = self.class.run([update_script, env_id, hook_env.image_url])
        hook_env.download_succeeded checksum
      rescue DownloadException => e
        hook_env.download_failed e.message
      end
    end
  end
end
