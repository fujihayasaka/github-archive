# typed: true
# frozen_string_literal: true

module GitHub
  module Aqueduct
    class Import
      def self.run
        imported = Hash.new { |h, k| h[k] = 0 }

        GitHub.job_coordination_redis.smembers("resque:queues").each do |queue|
          puts "Migrating resque queue #{queue}"

          queue_key = "resque:queue:#{queue}"

          while encoded = GitHub.job_coordination_redis.lpop(queue_key)
            begin
              decoded = GitHub::JSON.decode(encoded)
            rescue Yajl::ParseError
              GitHub.job_coordination_redis.lpush(queue_key, encoded)
              puts "#{queue} resque jobs aren't encoded as JSON, skipping..."
              break
            end

            begin
              job = ActiveJob::Base.deserialize(decoded["args"]&.first)
            rescue NameError, ActiveJob::DeserializationError, TypeError
              GitHub.job_coordination_redis.lpush(queue_key, encoded)
              puts "#{queue} resque jobs aren't deserializable ActiveJobs, skipping..."
              break
            end

            result = GitHub::Aqueduct::Job.enqueue_active_job(job)
            if result.ok?
              imported[job.queue_name] += 1
            else
              GitHub.job_coordination_redis.lpush(queue_key, encoded)
              puts "Failed to import job from #{queue}: #{result.error}, skipping..."
              break
            end
          end

          GitHub.job_coordination_redis.srem("resque:queues", queue)
        end

        imported
      rescue => e # rubocop:todo Lint/GenericRescue
        puts "Failed to import resque jobs: #{e}, skipping..."
        imported
      end
    end
  end
end
