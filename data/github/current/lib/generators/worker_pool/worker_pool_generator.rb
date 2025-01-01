# typed: true
# frozen_string_literal: true

class WorkerPoolGenerator < Rails::Generators::NamedBase
  source_root File.expand_path("templates", __dir__)

  DEPLOYMENT_TYPE = %w[kubernetes].freeze
  SUPPORTED_ENVIRONMENTS = %w[production proxima].freeze

  # Optional parameters
  class_option :deployment_type, type: :string, required: false, default: "kubernetes", desc: "The worker pool deployment type (kubernetes or vm)."
  class_option :environment, type: :string, required: false, default: "production", desc: "The environment the worker pool is deployed to (production or proxima)."
  class_option :buckets, type: :array, required: false, default: %w[30m 2h], desc: "The dynamic job queue prioritization buckets."
  class_option :replicas, type: :numeric, required: false, default: 1, desc: "The number of replica count per deployment and k8s cluster."

  def validate_options!
    if !name.ends_with?("worker")
      raise Thor::Error.new "Invalid worker pool name: #{name}. Must end with 'worker' to provide context in the codebase"
    end

    if !DEPLOYMENT_TYPE.include?(options[:deployment_type])
      raise Thor::Error.new "Invalid deployment type: #{options[:deployment_type]}. Must be one of: #{DEPLOYMENT_TYPE.join(", ")}"
    end

    if !SUPPORTED_ENVIRONMENTS.include?(options[:environment])
      raise Thor::Error.new "Invalid environment: #{options[:environment]}. Must be one of: #{SUPPORTED_ENVIRONMENTS.join(", ")}"
    end

    if options[:replicas] < 1
      raise Thor::Error.new "Invalid replica count: #{options[:replicas]}. Must be greater than 0"
    end
  end

  # Generate the worker pool initializer
  # Example: config/resqued/github-myworker-kube.rb
  def generate_worker_pool_initializer
    template "worker-pool-kube.rb.erb", worker_pool_rb_file
  end

  # Generate the k8s kustomize deployment file for the worker pool
  # and run kustomize build to generate the final k8s resources
  # Example:
  # - config/kustomize/base/production/aqueduct/deployments/myworker.yaml
  # - config/kubernetes/production/deployments/indexworker.yaml
  def generate_kubernetes_deployment
    template "worker-pool-k8s-deployment.yaml.erb", "#{kustomize_folder_for_environment}/aqueduct/deployments/#{pool_name}.yaml"
    existing_resources = YAML.safe_load(File.read("#{kustomize_folder_for_environment}/kustomization.yaml")).dig("resources")
    existing_resources.push("aqueduct/deployments/#{pool_name}.yaml")
    existing_resources.uniq!
    gsub_file(
      "#{kustomize_folder_for_environment}/kustomization.yaml",
      /resources:.*/m,
      "resources:\n#{existing_resources.sort.map { |resource| "  - #{resource}" }.join("\n")}\n"
    )
    generate_kubernetes_config_from_kustomize
  end

  no_commands do
    def pool_name
      name.underscore.dasherize
    end

    def github_role
      pool_name.to_sym
    end

    def github_pool_name
      "github-#{pool_name}"
    end

    def worker_pool_rb_file
      "config/resqued/#{github_pool_name}-kube.rb"
    end

    def kustomize_folder_for_environment
      "config/kustomize/base/#{options[:environment]}"
    end

    def generate_kubernetes_config_from_kustomize
      in_root do
        run "gh kustomize build"
      end
    end
  end

end
