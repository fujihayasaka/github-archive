# frozen_string_literal: true

# TODO: Refactor this class to delegate to github/dependabot-action locally -or- remove it entirely
#
# See: https://github.com/github/dependabot-updates/issues/1664
module RunUpdater
  class Docker
    attr_reader :job, :job_token, :credentials_token, :instance_type, :priority

    def initialize(job, job_token, credentials_token, instance_type, priority)
      @job = job
      @job_token = job_token
      @credentials_token = credentials_token
      @instance_type = instance_type
      @priority = priority
    end

    def run
      container = ::Docker::Container.create(
        "Image" => "dependabot/dependabot-updater",
        "Env" => [
          "DEPENDABOT_JOB_ID=#{job.id}",
          "DEPENDABOT_JOB_TOKEN=#{job_token}",
          "DEPENDABOT_API_URL=http://docker.for.mac.localhost:3001",
        ],
      )
      container.start

      Thread.new do
        container.attach do |stream, chunk|
          chunk.each_line do |line|
            puts "container[#{stream}]: #{line}" # rubocop:disable Rails/Output
          end
        end
        container.wait
      end
    end
  end
end
