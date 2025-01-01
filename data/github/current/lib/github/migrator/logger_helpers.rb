# typed: true
# frozen_string_literal: true

require "open3"

module GitHub
  class Migrator
    module LoggerHelpers
      def log_memory_usage(fn, step, guid: nil, migratable_model: nil, migratable_resource: nil, actor: nil, attributes: {})
        tags = ["step:#{step}", "migrator_pid:#{process_id}"]
        tags << "guid:#{guid}" if guid.present?
        tags << "migratable_model:#{migratable_model}" if migratable_model.present?

        GitHub.dogstats.gauge("migrator.import.rss_memory", get_mem, tags: tags)
      end

      def get_mem
        stdout, stderr, status = Open3.capture3("ps", "-o", "rss", "#{$$}")
        stdout.split("\n").last.to_i
      end

      def process_id
        $$
      end
    end
  end
end
