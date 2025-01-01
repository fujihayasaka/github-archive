# typed: false
# frozen_string_literal: true

require "unicorn"

class Unicorn::ProcessName
  include Singleton

  def initialize
    @info = {
      domain: GitHub.host_name,
      sha: GitHub.current_sha[0, 7],
      worker_number: 99,
      total_requests: 0,
      requests_per_second: 0,
      average_response_time: 0,
      percentage_active: 0
    }
  end

  def procline
    "unicorn %<domain>s[%<sha>s] worker[%<worker_number>02d]: %<total_requests>5d reqs, %<requests_per_second>4.1f req/s, %<average_response_time>4dms avg, %<percentage_active>5.1f%% util" % @info
  end

  def update(new_info)
    @info.update(new_info)
  end

  def setproctitle
    # TODO: ideally this would use Process.setproctitle, but we need to first make sure nobody relies on $0 changing
    $0 = procline
  end
end
