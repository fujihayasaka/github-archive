# typed: true
# frozen_string_literal: true

class Stafftools::FileserversController < StafftoolsController # rubocop:todo GitHub/ControllersShouldHaveTests
  include ActionView::Helpers::NumberHelper
  include GitHub::FileserverHealth

  def index
    fileservers = get_fs
    df = get_disk_stats(fileservers)
    loadavg = get_loadavg(fileservers)
    cpus = get_cpu_count(fileservers)
    ops = get_git_op_count(fileservers)
    repos_per_host = get_repo_replica_count(fileservers)
    gists_per_host = get_gist_replica_count(fileservers)
    gitmon, _ = parallel_gitmon(fileservers, "scheduler_health", {})

    @statuses = fileservers.map do |fs, _|
      host = fs.name
      {
        host: host,
        disk_free: df[host] && (100 * df[host]),
        cpu_load: loadavg[host],
        cpu_count: cpus[host],
        git_ops: ops[host],
        num_repos: repos_per_host[host],
        num_gists: gists_per_host[host],
        cpu_health: gitmon && gitmon[host] && gitmon[host][0],
        mem_health: gitmon && gitmon[host] && gitmon[host][1],
        queue_health: gitmon && gitmon[host] && gitmon[host][2],
      }
    end

    case params[:sort]
      # Rules for sorting:
      #   - put the important stuff at the top
      #   - put nils (missing values) at the bottom
      #   - secondarily sort by short hostname
    when "disk_free"     # ascending
      @statuses.sort_by! { |x| [x[:disk_free] || 1000,     pad_host_number(x[:host])] }
    when "cpu_load"      # descending
      @statuses.sort_by! { |x| [-x[:cpu_load].to_f / (x[:cpu_count] || 1), pad_host_number(x[:host])] }
    when "git_ops"      # descending
      @statuses.sort_by! { |x| [-x[:git_ops].to_i,          pad_host_number(x[:host])] }
    when "num_repos"     # descending
      @statuses.sort_by! { |x| [-x[:num_repos].to_i,        pad_host_number(x[:host])] }
    when "num_gists"     # descending
      @statuses.sort_by! { |x| [-x[:num_gists].to_i,        pad_host_number(x[:host])] }
    when "cpu_health"    # ascending
      @statuses.sort_by! { |x| [x[:cpu_health] || 1000,    pad_host_number(x[:host])] }
    when "mem_health"    # ascending
      @statuses.sort_by! { |x| [x[:mem_health] || 1000,    pad_host_number(x[:host])] }
    when "queue_health"  # ascending
      @statuses.sort_by! { |x| [x[:queue_health] || 1000,  pad_host_number(x[:host])] }
    else                 # host
      @statuses.sort_by! { |x|    pad_host_number(x[:host]) }
    end

    render "stafftools/fileservers/index", layout: "stafftools"
  end

  helper_method :short_host, :fmt_pct

  CRITICAL_BELOW = {
    disk_free: 10,
    cpu_health: 10,
    mem_health: 10,
    queue_health: 10,
  }
  WARN_BELOW = {
    disk_free: 20,
    cpu_health: 60,
    mem_health: 60,
    queue_health: 60,
  }
  CRITICAL_ABOVE = {
    git_ops: 1000,
  }
  WARN_ABOVE = {
    git_ops: 250,
  }
  CPU_LOAD_CRITICAL = 1.25
  CPU_LOAD_WARNING =  0.75

  def status_category(status, field) # rubocop:todo GitHub/UseRestfulActions
    if CRITICAL_BELOW.key?(field) && status[field] && status[field] < CRITICAL_BELOW[field]
      return "fileserver-status-critical"
    end

    if CRITICAL_ABOVE.key?(field) && status[field] && status[field] > CRITICAL_ABOVE[field]
      return "fileserver-status-critical"
    end

    if WARN_BELOW.key?(field) && status[field] && status[field] < WARN_BELOW[field]
      return "fileserver-status-warning"
    end

    if WARN_ABOVE.key?(field) && status[field] && status[field] > WARN_ABOVE[field]
      return "fileserver-status-warning"
    end

    if field == :cpu_load && status[:cpu_load] && status[:cpu_count]
      if status[:cpu_load] / status[:cpu_count] > CPU_LOAD_CRITICAL
        return "fileserver-status-critical"
      elsif status[:cpu_load] / status[:cpu_count] > CPU_LOAD_WARNING
        return "fileserver-status-warning"
      end
    end

    "fileserver-status-ok"
  end
  helper_method :status_category

  private

  def pad_host_number(str)
    str.sub(/\d+/) { |n| "%05d" % n.to_i }
  end
end
