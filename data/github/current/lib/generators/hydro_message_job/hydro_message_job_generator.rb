# typed: false
# frozen_string_literal: true

require "generators/background_job_queue/background_job_queue_generator"

class HydroMessageJobGenerator < Rails::Generators::NamedBase
  source_root File.expand_path("templates", __dir__)

  class_option :service, type: :string, required: true,
    desc: "The service that owns the job (used for queue configuration)"
  class_option :topic, type: :string, required: true,
    desc: "The hydro topic the messages will be coming from"
  class_option :schema, type: :string, required: false,
    desc: "The hydro message schema expected in this job"
  class_option :queue, type: :string, required: false,
    desc: "The hydro message job queue this job will come from"
  class_option :tier, type: :numeric, required: false,
    desc: "The hydro message job queue tier this job will come from"
  class_option :enterprise, type: :boolean, required: false, default: false,
    desc: "Whether to configure the enterprise (GHES) bridge to run these jobs"
  class_option :proxima, type: :boolean, required: false, default: false,
    desc: "Whether to configure proxima workers to run these jobs"
  class_option :staff, type: :boolean, required: false, default: false,
    desc: "Whether this queue should be worked on in staff environments (lab, garage, review-labs)"
  class_option :base_class, type: :string, required: false, default: "HydroMessageJob",
    desc: "The base class for the job"
  class_option :worker_type, type: :string, required: false, default: "hydro",
    desc: "The dotcom worker type that should work this queue - one of #{BackgroundJobQueueGenerator::DOTCOM_WORKER_TYPES.join(', ')}"
  class_option :proxima_worker_type, type: :string, required: false, default: "shared",
    desc: "The proxima worker type that should work this queue - one of #{BackgroundJobQueueGenerator::PROXIMA_WORKER_TYPES.join(', ')}"

  def generate_hydro_processor_class
    template "hydro_message_job.rb.erb", "app/jobs/#{file_path}.rb"
  end

  def generate_hydro_processor_test
    template "hydro_message_job_test.rb.erb", "test/jobs/#{file_path}_test.rb"
  end

  def generate_background_job_queue_configs
    subtask_options = [
      "--service", options[:service],
      "--dotcom-worker-type", worker_type,
      "--development",
      "--no-execution-time-slo",
    ]
    if options[:tier]
      subtask_options.push("--tier", options[:tier])
    else
      subtask_options.push("--tier", BackgroundJobQueueGenerator::DEFAULT_TIER)
    end
    if options[:enterprise]
      subtask_options.push("--enterprise-priority", "low")
    else
      subtask_options.push("--no-enterprise")
    end
    if options[:proxima]
      subtask_options.push("--proxima-worker-type", options[:proxima_worker_type])
    else
      subtask_options.push("--no-proxima")
    end
    if options[:staff]
      subtask_options.push("--staff")
    else
      subtask_options.push("--no-staff")
    end
    invoke("background_job_queue", [queue_name], subtask_options)
  end

  def update_development_bridge
    add_topic_config("dotcom")
  end

  def update_enterprise_bridge
    add_topic_config("enterprise") if options[:enterprise]
  end

  def update_kafka_lite_server
    script_path = File.join(destination_root, "config/kafka-server-seeds")
    server_script_contents = File.read(script_path)
    if !server_script_contents.include?(options[:topic])
      last_line = server_script_contents.lines.last.chomp
      if !last_line.end_with?("\\")
        insert_into_file script_path, " \\", after: last_line, force: true
      end
      append_to_file "config/kafka-server-seeds", "--seed-topic #{options[:topic]}:1\n"
    end
  end

  def print_next_steps
    say "\n\nReminder: External Configuration is required!\n\n", :red

    say "1. Make sure that the topic's configuration in hydro-schemas has been updated to include the bridge configuration"
    if options[:enterprise]
      say "2. Make sure that the topic is available in GHES by checking that it exists in https://github.com/github/hydro-schemas/tree/main/topic-configuration/production/enterprise"
    end

    say "For information on this, please see the docs at https://thehub.github.com/epd/engineering/products-and-services/internal/hydro/guides/hydro-message-job-processing/#deployment"
  end

  no_commands do
    DEFAULT_APP = "github-<%= Rails.env %>"

    def queue_name
      options[:queue] || class_name.underscore.sub("_job", "")
    end

    def schema_name
      options[:schema] || options[:topic].sub("cp1-iad.ingest.", "")
    end

    def worker_type
      options[:worker_type]
    end

    def add_topic_config(runtime)
      mapping = YAML.load_file("config/aqueduct_hydro_message_bridge/#{runtime}.yml")
      mapping[options[:topic]] ||= []

      return if mapping[options[:topic]].any? do |mapping|
        mapping["app"] == DEFAULT_APP &&
          mapping["queue"] == queue_name
      end

      mapping[options[:topic]].push({ "app" => DEFAULT_APP, "queue" => queue_name })

      gsub_file("config/aqueduct_hydro_message_bridge/#{runtime}.yml", /---.*/m, mapping.sort.to_h.to_yaml)
    end

    def base_class_definition
      "< #{options[:base_class]}"
    end

    def test_base_class_definition
      "< GitHub::TestCase"
    end
  end
end
