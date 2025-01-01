# Official puma docs are here: https://msp-greg.github.io/puma/#thread-pool
# Most of these settings were pulled (with accompanying doc) from https://devcenter.heroku.com/articles/deploying-rails-applications-with-the-puma-web-server with a stock configuration.

# See "Threads" and "Thread count value" in heroku doc
pod_type = ENV["DG_POD_TYPE"]&.downcase
# Note: Increasing threads may not work how you think. Threads is just the allowed number of requests
# to be concurrently processed, *not* processed in parallel. Our Ruby application won't use more than core
# (unless a dependency starts background processes, which we do not currently know of happening), and puma
# can scale out to multi core with the use of workers (not threads). Total capacity for a given node
# would be workers * threads.
# The number of threads being increased can decrease performance ( https://www.speedshop.co/2020/05/11/the-ruby-gvl-and-scaling.html )
threads 5, 5

# This value should closely align with the # of CPUs allocated in deployment.yaml for the appropriate environment.
# Puma runs "unclustered" by default (workers = 0), which means that no more than one process will be utilized by Puma.
# We're explicitly setting it here because it impacts kube capacity and we want it to be obvious to readers of this config how many workers there are.
if ENV["ENTERPRISE"]
  # In Enterprise, we run inside of a single container and may want to increase the number of worker processes via environment variable.
  workers (ENV["ENTERPRISE_DEPENDENCY_GRAPH_API_PUMA_WORKERS"] || 2).to_i
else
  # For dotcom, we're running in single mode because multiprocess concurrency is handled by Moda/K8s pod replicas
  workers 0
end

bind ENV.fetch("PUMA_BIND") { "tcp://0.0.0.0:9596" }

environment ENV.fetch("RAILS_ENV") { "development" }

app_dir = File.expand_path("../..", __FILE__)

# Don't redirect STDOUT if our ENV wants STDOUT logging (Moda/Kube)
unless ENV["RAILS_LOG_TO_STDOUT"]
  stdout_redirect "#{app_dir}/log/#{get(:environment)}.log", "#{app_dir}/log/#{get(:environment)}.log", true
end

unless get(:environment) == "development"
  pidfile "#{app_dir}/tmp/pids/puma.pid"
end

# Allow puma to be restarted by `rails restart` command.
plugin :tmp_restart

# Send puma metrics to statsd via a background thread
plugin :statsd
