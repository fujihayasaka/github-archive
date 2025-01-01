# typed: true
# frozen_string_literal: true

require "serviceowners"
require "resqued/duration_parser"
require "resqued/should_start_within_priority"

class BackgroundJobQueueGenerator < Rails::Generators::NamedBase
  DURATION_PARSER = Resqued::DurationParser.new


  # Avg P99 execution time for all our queues in the last 30 days
  DEFAULT_EXECUTION_TIME_SLO = 3000
  DEFAULT_TIER = 1

  # By default, if not specified on the job queue generator, we will set the job to
  # have a scheduling_hints.should_start_within value of 1h so the developer
  # is aware they need to change it. Otherwise, we could wrongly prioritize jobs that are not time sensitive.
  DEFAULT_SHOULD_START_WITHIN = Resqued::ShouldStartWithinPriority::SHOULD_START_WITHIN_DEFAULT_VALUE

  DOTCOM_WORKER_TYPES = %w[high low slow hydro push].freeze
  TIER_TYPES = [0, 1, 2].freeze
  ENTERPRISE_PRIORITIES = %w[high low].freeze
  PROXIMA_PRIORITIES = %w[high low].freeze

  class_option :service, type: :string, required: false, desc: "The service that owns this job queue"
  class_option :execution_time_slo_ms, type: :numeric, required: false, desc: "The execution time SLO for this queue in milliseconds"
  class_option "no-execution-time-slo", type: :boolean, required: false, desc: "Whether this queue should have its execution time SLO enforced"
  class_option :dotcom_worker_type, type: :string, required: false, desc: "The dotcom worker type that should work this queue - one of #{DOTCOM_WORKER_TYPES.join(', ')}"
  class_option :tier, type: :numeric, required: true, desc: "The queue tier - one of #{TIER_TYPES.join(', ')}"
  class_option :should_start_within, type: :string, required: false, default: DEFAULT_SHOULD_START_WITHIN, desc: "The ideal time to deliver a job since it was enqueued - a value with the format /\d+[smhd]/"
  class_option "no-dotcom", type: :boolean, required: false, desc: "Whether this queue should be worked on in dotcom"
  class_option :enterprise_priority, type: :string, required: false, desc: "The priority of this queue in enterprise - one of #{ENTERPRISE_PRIORITIES.join(', ')}"
  class_option "no-enterprise", type: :boolean, required: false, default: false, desc: "Don't work the queue in enterprise"
  class_option :proxima_priority, type: :string, required: false, desc: "The priority of this queue in proxima - one of #{PROXIMA_PRIORITIES.join(', ')}"
  class_option "no-proxima", type: :boolean, required: false, default: false, desc: "Don't work the queue in proxima"
  class_option :staff, type: :boolean, desc: "Whether this queue should be worked on in staff environments (lab, garage, review-labs)"
  class_option :development, type: :boolean, desc: "Whether this queue should be worked on in development"

  def validate_options!
    if options["no-execution-time-slo"] && options[:execution_time_slo_ms]
      raise Thor::Error.new("You can't specify a queue execution time slo with the no-execution-time-slo option")
    end
    if options["no-dotcom"] && options[:dotcom_worker_type]
      raise Thor::Error.new("You can't specify a dotcom worker type if you're not working the queue in dotcom")
    end
    if options["no-enterprise"] && options[:enterprise_priority]
      raise Thor::Error.new("You can't specify an enterprise priority if you're not working the queue in enterprise")
    end
    if options["no-proxima"] && options[:proxima_priority]
      raise Thor::Error.new("You can't specify a proxima priority if you're not working the queue in proxima")
    end

    if options[:execution_time_slo_ms] && options[:execution_time_slo_ms] <= 0
      raise Thor::Error.new("You can't specify an execution time SLO of 0 or less")
    end
    if options[:dotcom_worker_type]
      unless DOTCOM_WORKER_TYPES.include?(options[:dotcom_worker_type])
        raise Thor::Error.new("Invalid dotcom worker type: #{options[:dotcom_worker_type]}. Must be one of #{DOTCOM_WORKER_TYPES.join(', ')}")
      end
    end
    if options[:tier]
      unless TIER_TYPES.include?(options[:tier])
        raise Thor::Error.new("Invalid queue tier value: #{options[:tier]}. Must be one of #{TIER_TYPES.join(', ')}")
      end
    end
    if options[:should_start_within]
      unless DURATION_PARSER.validate(options[:should_start_within])
        raise Thor::Error.new("Invalid queue max delivery delay value: #{options[:should_start_within]}. Must a value with the format /\d+[smhd]/")
      end
    end
    if options[:enterprise_priority]
      unless ENTERPRISE_PRIORITIES.include?(options[:enterprise_priority])
        raise Thor::Error.new("Invalid enterprise priority: #{options[:enterprise_priority]}. Must be one of #{ENTERPRISE_PRIORITIES.join(', ')}")
      end
    end
    if options[:proxima_priority]
      unless PROXIMA_PRIORITIES.include?(options[:proxima_priority])
        raise Thor::Error.new("Invalid proxima priority: #{options[:proxima_priority]}. Must be one of #{PROXIMA_PRIORITIES.join(', ')}")
      end
    end
  end

  def generate_configuration
    existing_configuration = if File.exist?(file_path)
      YAML.safe_load(File.read(file_path), aliases: true)
    else
      create_file file_path
      {}
    end

    existing_configuration[name] = {
      scheduling_hints: {
        tier: options[:tier],
        should_start_within: options[:should_start_within],
      },
      dotcom: build_dotcom_configuration,
      enterprise: build_enterprise_configuration,
      proxima: build_proxima_configuration,
      staff: build_simple_configuration(options[:staff], "Should this queue be worked on in staff environments (lab, garage, review-labs)?"),
      development: build_simple_configuration(options[:development], "Should this queue be enabled in development?"),
    }

    existing_configuration[name][:execution_time_slo_ms] = build_execution_time_slo_configuration if !options["no-execution-time-slo"]

    existing_configuration[name] = existing_configuration[name].deep_stringify_keys

    File.open(file_path, "w") do |file|
      file.write(existing_configuration.to_yaml)
    end
  end

  def update_serviceowners
    serviceowners = Serviceowners::Main.new(runtime_env: Serviceowners::RuntimeEnv.new({ patterns_path: serviceowners_path }))

    if serviceowners.spec_for_path(file_path).nil?
      serviceowners_entries = File.read(serviceowners_path).lines.map(&:strip)
      last_service_index = serviceowners_entries.rindex { |line| line.split(" ").last == ":#{service}" } || serviceowners_entries.count - 1
      relative_path = File.expand_path(file_path).delete_prefix("#{Rails.root}/")
      serviceowners_entries.insert(last_service_index + 1, "#{relative_path} :#{service}")

      File.write(File.join(serviceowners_path), serviceowners_entries.join("\n") + "\n")
    end
  end

  private

  def service
    @service ||= (options[:service] || ask("Which service owns this queue?")).sub(/\Agithub\//, "")
  end

  def build_execution_time_slo_configuration
    if options[:execution_time_slo_ms]
      options[:execution_time_slo_ms]
    else
      ask("What should the execution time SLO be in ms?", default: DEFAULT_EXECUTION_TIME_SLO).to_i
    end
  end

  def build_dotcom_configuration
    if options["no-dotcom"]
      false
    elsif !options["no-dotcom"] && !options[:dotcom_worker_type]
      if yes?("Should this queue be worked on in dotcom?")
        dotcom_configuration_hash(ask("Which type of worker should work this queue?", default: "low", limited_to: DOTCOM_WORKER_TYPES))
      else
        false
      end
    else
      dotcom_configuration_hash(options[:dotcom_worker_type])
    end
  end

  def dotcom_configuration_hash(worker_type)
    machine_type = worker_type == "slow" ? "vm" : "kube"
    { "#{worker_type}worker" => { machine_type => { "pool_workers" => true } } }
  end

  def build_enterprise_configuration
    if options["no-enterprise"]
      false
    elsif !options["no-enterprise"] && !options[:enterprise_priority]
      if yes?("Should this queue be worked on in enterprise?")
        ask("Which priority should this queue have in enterprise?", default: "low", limited_to: ENTERPRISE_PRIORITIES)
      else
        false
      end
    else
      options[:enterprise_priority]
    end
  end

  def build_proxima_configuration
    if options["no-proxima"]
      false
    elsif !options["no-proxima"] && !options[:proxima_priority]
      if yes?("Should this queue be worked on in proxima?")
        ask("Which priority should this queue have in proxima?", default: "low", limited_to: PROXIMA_PRIORITIES)
      else
        false
      end
    else
      options[:proxima_priority]
    end
  end

  def build_simple_configuration(option_value, question)
    if option_value.nil?
      ask(question, default: "yes", limited_to: %w[yes no]) == "yes"
    else
      option_value
    end
  end

  def file_path
    File.expand_path("config/background_job_queues/#{service}.yml", destination_root)
  end

  def serviceowners_path
    File.expand_path("SERVICEOWNERS", destination_root)
  end
end
