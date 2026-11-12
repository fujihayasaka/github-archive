# frozen_string_literal: true

namespace :throttler do
  task server: :environment do
    throttler = Throttlers.pull_request
    FileUtils.touch("/tmp/throttler_started")
    throttler.print_tickets
  end

  task health_check: :environment do
    puts <<-MSG
    Healthy at #{Throttlers.pull_request.health_check}
    MSG
  end

  task limits: :environment do
    rate_limit = Throttlers.pull_request.rate_limit
    puts <<-MSG
    PR creation limited to #{rate_limit.limit} requests per #{rate_limit.frequency} seconds
    MSG
  end

  task :set_limits, %i(limit frequency) => [:environment] do |_task, args|
    rate_limit = Throttlers.pull_request.rate_limit
    rate_limit.set_limit(args[:limit], args[:frequency])
    puts <<-MSG
    New limit for PR throttler set.
    #{rate_limit.limit} requests per #{rate_limit.frequency} seconds
    MSG
  end

  task ping: :environment do
    throttler = Throttlers.pull_request
    loop do
      throttler.throttle do
        puts "ping #{Time.zone.now}"
      end
    end
  end
end
