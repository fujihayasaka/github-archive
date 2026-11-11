# typed: false
# frozen_string_literal: true

require "active_job"
require "timestamp"

autoload "ApplicationJob", "#{GitHub::AppEnvironment.root}/packages/application/app/jobs/application_job.rb"
autoload "BatchedJob", "#{GitHub::AppEnvironment.root}/packages/application/app/jobs/batched_job.rb"
autoload "WaitForReplication", "#{GitHub::AppEnvironment.root}/packages/substrate/app/models/wait_for_replication.rb"

Dir[File.expand_path("#{GitHub::AppEnvironment.root}/app/jobs/*.rb", __FILE__)].each do |file|
  class_name = File.basename(file.sub(/\.(rb)$/, "")).gsub(/(?:^|_)(.)/) { $1.upcase }.gsub(/Github/, "GitHub")
  autoload class_name, file
end
