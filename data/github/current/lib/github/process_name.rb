# typed: true
# frozen_string_literal: true

class GitHub::ProcessName
  include Singleton

  def initialize
    @info = {
      rack_server: "unicorn",
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
    "%<rack_server>s %<domain>s[%<sha>s] worker[%<worker_number>02d]: %<total_requests>5d reqs, %<requests_per_second>4.1f req/s, %<average_response_time>4dms avg, %<percentage_active>5.1f%% util" % @info
  end

  def update(new_info)
    @info.update(new_info)
  end

  def setproctitle
    Process.setproctitle(procline)
  end
end
