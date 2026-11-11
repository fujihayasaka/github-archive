# frozen_string_literal: true

require "open3"

module DockerHelper
  extend self

  TIMEOUT = 60
  MINIMUM_DOCKER_FREE_SPACE_GB = 12

  def ensure_docker_running
    return if docker_running?

    if ENV["CODESPACES"]
      # Call Codespaces' standard docker-in-docker start script as it does not
      # use `supervisorctl` to (re)start docker.
      system("sudo /usr/local/share/docker-init.sh")
      # This was chosen arbitrarily; feel free to bump as desired.
      sleep 2
      return if docker_running?
    end

    puts ""
    puts ""
    puts ""
    puts "Docker is required to complete bootstrapping for local"
    puts "development, but is not available."

    abort unless $stdin.tty?

    puts
    puts "Please start the Docker service before continuing, and ensure you"
    puts "wait a minute for it to become available before continuing."

    puts ""
    print "Press enter to continue..."
    $stdout.flush
    $stdin.gets

    return if docker_running?

    puts ""
    puts ""
    puts ""
    puts "Oops, looks like Docker still isn't working properly."
    abort
  end

  def docker_running?
    # system should work here but doesn't reliably with &>/dev/null so use Open3.capture3 instead.
    stdout, stderr, status = Open3.capture3("docker ps")
    status.success?
  end

  def ensure_docker_space_available
    df_output = docker_df_output

    return if df_output.nil?

    _table_headers, overlay_data = df_output.lines
    available_docker_space_kb = overlay_data.split[3].to_i
    available_docker_space_gb = available_docker_space_kb / 1024 / 1024

    if available_docker_space_gb < MINIMUM_DOCKER_FREE_SPACE_GB
      puts ""
      puts "Cowardly refusing to continue because the Docker VM"
      puts "does not have enough space to complete the bootstrap."
      puts ""
      puts "You can also try to decrease the space that Docker is using by running"
      puts "'docker system prune --all', which will remove all unused containers, networks, and images,"
      puts "and then by waiting a minute or two before bootstrapping again."
      abort
    end
  end

  private

  # Determine Docker filesystem disk space while attempting to avoid pulling images.
  #
  # First tries a host-local check by getting Docker's data root directory
  # via `docker info` and running `df` on it directly. This works on Linux
  # where Docker stores data on the host filesystem and avoids any network
  # traffic (and thus image pulls) when it succeeds.
  #
  # Falls back to `docker run alpine df -P /` for environments like macOS
  # Docker Desktop where Docker's data root lives inside a VM and isn't
  # accessible from the host. This fallback may trigger an `alpine` image
  # pull if the image is not already present locally.
  #
  # Returns the `df -P` output string, or nil if both methods fail.
  def docker_df_output
    # Try the host-local approach first to avoid image pulls when possible:
    # get Docker's root dir and run df on the host.
    docker_root_stdout, _stderr, status = Open3.capture3("docker info --format '{{.DockerRootDir}}'")
    if status.success?
      docker_root = docker_root_stdout.strip
      unless docker_root.empty?
        df_stdout, _df_stderr, df_status = Open3.capture3("df", "-P", docker_root)
        if df_status.success? && !df_stdout.empty? && df_stdout.lines.length >= 2
          return df_stdout
        end
      end
    end

    # Fall back to running a container (needed on macOS Docker Desktop where
    # the Docker root directory is inside a VM).
    stdout, stderr, status = Open3.capture3("docker run --rm -i alpine df -P /")
    if !status.success? || stdout.nil? || stdout.empty? || stdout.lines.length < 2
      puts "Warning: Could not determine Docker disk space."
      puts "  Local df check failed (Docker root dir not accessible on host)."
      puts "  Container-based check also failed:"
      puts "  #{stderr}" unless stderr.nil? || stderr.strip.empty?
      return nil
    end

    stdout
  end
end

if __FILE__ == $0
  DockerHelper.ensure_docker_running
end
