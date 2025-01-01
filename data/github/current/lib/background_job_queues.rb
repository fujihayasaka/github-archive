# typed: true
# frozen_string_literal: true

require "resqued/duration_parser"

class BackgroundJobQueues
  autoload :ConfigurationEvaluationContext, "background_job_queues/configuration_evaluation_context"

  DEFAULT_YAML_DIRECTORY = "config/background_job_queues/"
  DEFAULT_MONITOR_QUEUES_FILE_PATH = DEFAULT_YAML_DIRECTORY + "worker_monitors.yml"
  SIMPLE_ENVIRONMENTS = %i[development staff].freeze
  ALLOWED_ENVIRONMENTS = %w{
    dotcom
    proxima
    enterprise
    staff
    development
    staging
  }.freeze

  class << self
    delegate :apply_worker_pool_env, :apply_dotcom, :apply_staging, :apply_enterprise, :apply_simple, :queue_configurations, :queue_configurations_for_environment, :queue_configurations_for_worker_pool_and_type, :invalid_queue_configurations, :allowed_environments, :queue_slos, :monitor_queue_names, to: :instance
  end

  def self.instance
    @instance ||= new
  end

  def initialize(yaml_directory: DEFAULT_YAML_DIRECTORY, monitor_queues_path: DEFAULT_MONITOR_QUEUES_FILE_PATH)
    @yaml_directory = yaml_directory.start_with?("/") ? yaml_directory : Rails.root.join(yaml_directory)
    @monitor_queues_path = monitor_queues_path.to_s.start_with?("/") ? monitor_queues_path : Rails.root.join(monitor_queues_path)
    @duration_parser = Resqued::DurationParser.new
    @worker_pool_configurations = {}
  end

  def apply_worker_pool_env(resqued_config, environment: :dotcom, worker_role:, machine_type:)
    configuration = worker_pool_configurations(environment: environment).dig(worker_role, machine_type)

    configuration[:pool_workers].each do |queue_name, options|
      resqued_config.queue queue_name, **options
    end

    configuration[:dedicated_workers].each do |queue_name, options_collection|
      options_collection.each do |options|
        resqued_config.worker queue_name, **options
      end
    end
  end

  # Helper method, use apply_worker_pool_env for more flexibility
  def apply_dotcom(resqued_config, worker_role:, machine_type:)
    apply_worker_pool_env(resqued_config, environment: :dotcom, worker_role: worker_role, machine_type: machine_type)
  end

  def apply_enterprise(resqued_config, high_priority_worker_count:, low_priority_worker_count:)
    enterprise_queues = queue_configurations_for_environment(environment: :enterprise).each_with_object({ high_priority: [], low_priority: [] }) do |(queue_name, queue_configuration), result|
      if queue_configuration[:enterprise].to_sym == :high
        result[:high_priority].push(queue_name)
      else
        result[:low_priority].push(queue_name)
      end
    end

    high_priority_worker_count.times do
      resqued_config.worker(*enterprise_queues[:high_priority], shuffle_queues: true)
    end

    low_priority_worker_count.times do
      resqued_config.worker(*(enterprise_queues[:high_priority] + enterprise_queues[:low_priority]), shuffle_queues: true)
    end
  end

  def apply_staging(resqued_config, worker_role:, machine_type:)
    apply_worker_pool_env(resqued_config, environment: :staging, worker_role: worker_role, machine_type: machine_type)
  end

  def apply_simple(resqued_config, environment:, queue_prefix: nil)
    raise ArgumentError, "environment must be one of: #{SIMPLE_ENVIRONMENTS}" unless SIMPLE_ENVIRONMENTS.include?(environment)

    queue_configurations_for_environment(environment: environment).each do |queue_name, _queue_configuration|
      resqued_config.queue "#{queue_prefix}#{queue_name}"
    end
  end

  def queue_configurations
    @queue_configurations ||= Dir["#{yaml_directory}/**/*.yml"].each_with_object({}) do |file_path, result|
      config = YAML.safe_load(
        ERB.new(
          File.read(file_path)
        ).result(ConfigurationEvaluationContext.evaluation_context),
        aliases: true
      ).transform_values! do |value|
        if value.is_a?(Hash)
          value.deep_symbolize_keys!

          # Hydrate the hash with useful information to be used at runtime
          # This will avoid extra calculations at runtime and business logic
          # to be spread across the codebase
          if value.dig(:scheduling_hints, :should_start_within)
            value[:scheduling_hints][:should_start_within_secs] =
              @duration_parser.get_duration_in_seconds(
                value.dig(:scheduling_hints, :should_start_within)
              )
          end
        end
        value
      end

      result.merge!(config) do |key|
        raise "Duplicate queue name: #{key}"
      end
    end
  end

  def queue_configurations_for_environment(environment:)
    queue_configurations.select do |_queue_name, queue_configuration|
      queue_configuration[environment]
    end
  end

  def invalid_queue_configurations(environment:)
    return {} if !ALLOWED_ENVIRONMENTS.include?(environment.to_s) || GitHub.enqueue_invalid_jobs_per_environment_enabled?
    queue_configurations.select do |_queue_name, queue_configuration|
      !queue_configuration[environment]
    end
  end

  def queue_slos
    @queue_slos ||= queue_configurations.each_with_object({}) do |(queue_name, queue_configuration), result|
      next unless queue_configuration[:execution_time_slo_ms]

      result[queue_name] = queue_configuration[:execution_time_slo_ms]
    end
  end

  def monitor_queue_names
    @monitor_queue_names = YAML.safe_load(
      ERB.new(
        File.read(@monitor_queues_path)
      ).result(ConfigurationEvaluationContext.evaluation_context)
    ).keys
  end

  def allowed_environments
    ALLOWED_ENVIRONMENTS
  end

  def queue_configurations_for_worker_pool_and_type(environment:, worker_role:, machine_type:)
    queue_configurations_for_environment(environment: environment).select do |_queue_name, config|
      config[environment].is_a?(Hash) &&
      config[environment].key?(worker_role) &&
      config[environment][worker_role].is_a?(Hash) &&
      config[environment][worker_role].key?(machine_type)
    end
  end

  private

  attr_reader :yaml_directory

  def worker_pool_configurations(environment: :dotcom)
    return @worker_pool_configurations[environment] if @worker_pool_configurations[environment]

    @worker_pool_configurations[environment] =
      queue_configurations_for_environment(environment: environment).each_with_object({}) do |(queue_name, queue_configuration), result|
        queue_configuration[environment].each do |worker_role, machine_type_configurations|
          machine_type_configurations.each do |machine_type, machine_type_configuration|
            result[worker_role] ||= {}
            result[worker_role][machine_type] ||= {
              pool_workers: {},
              dedicated_workers: {},
            }
            if machine_type_configuration[:pool_workers]
              result[worker_role][machine_type][:pool_workers][queue_name] = convert_options_shorthand(machine_type_configuration[:pool_workers])
            end
            if machine_type_configuration[:dedicated_workers]
              result[worker_role][machine_type][:dedicated_workers][queue_name] = convert_array_shorthand(machine_type_configuration[:dedicated_workers])
            end
          end
        end
      end
    @worker_pool_configurations[environment]
  end

  def dotcom_worker_role_configurations
    return @dotcom_worker_role_configurations if defined?(@dotcom_worker_role_configurations)

    @dotcom_worker_role_configurations = worker_pool_configurations(environment: :dotcom)
  end

  def convert_options_shorthand(options)
    if options == true
      {}
    else
      options
    end
  end

  def convert_array_shorthand(options)
    if options.is_a?(Array)
      options.map(&method(:convert_options_shorthand))
    elsif options.is_a?(Hash)
      if options.has_key?(:count)
        options.delete(:count).times.map { options }
      else
        [options]
      end
    else
      [convert_options_shorthand(options)]
    end
  end
end
