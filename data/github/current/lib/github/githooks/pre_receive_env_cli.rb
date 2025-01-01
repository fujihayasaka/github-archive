# typed: true
# frozen_string_literal: true

class GitHub::PreReceiveEnvCli

  class Error < StandardError
  end

  # Creates and returns a new PreReceiveEnvironment
  #
  # @param [String] env_name - Name of the environment to create
  # @param [Object] image_url - The url of the tarball we should download and extract
  # @param [Object] download_script - The script that downloads the tarball. Only override this for testing.
  # @return [PreReceiveEnvironment] - The environment we created
  def self.create_env(env_name, image_url, download_script = "/usr/local/share/enterprise/ghe-hook-env-update")
    raise Error, "an environment named '#{env_name}' already exists." if PreReceiveEnvironment.exists?(name: env_name)
    new_env = PreReceiveEnvironment.create(name: env_name, image_url: image_url, download_state: :in_progress)
    download_start_time = Time.now
    res = Progeny::Command.new(download_script, new_env.id.to_s, new_env.image_url)

    if res.status.success?
      new_env.update downloaded_at: download_start_time, checksum: res.out.chomp, download_state: :success
    else
      new_env.update download_state: :failed
      new_env.destroy
      raise Error, "There's been a problem downloading the image:
exit status: #{res.status.exitstatus}
stdout: #{res.out}
stderr: #{res.err}"
    end
    new_env
  end
end
