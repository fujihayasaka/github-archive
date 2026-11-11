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

  # Generate the k8s kustomize deployment files for the worker pool
  # and run kustomize build to generate the final k8s resources
  # Example:
  # - config/kustomize/base/production/aqueduct/deployments/myworker/kustomization.yaml
  # - config/kustomize/base/production/aqueduct/deployments/myworker/deployment-patches.yaml
  # - config/kubernetes/production/deployments/myworker.yaml
  def generate_kubernetes_deployment
    template "worker-pool-kustomization.yaml.erb", "#{aqueduct_deployments_folder}/#{pool_name}/kustomization.yaml"
    template "worker-pool-deployment-patches.yaml.erb", "#{aqueduct_deployments_folder}/#{pool_name}/deployment-patches.yaml"
    update_aqueduct_kustomization_resources
    generate_kubernetes_config_from_kustomize
  end

  def update_aqueduct_kustomization_resources
    kustomization_path = "#{aqueduct_folder}/kustomization.yaml"
    absolute_path = File.expand_path(kustomization_path, destination_root)
    return unless File.exist?(absolute_path)

    existing_resources = YAML.safe_load(File.read(absolute_path)).dig("resources")
    existing_resources.push("deployments/#{pool_name}")
    existing_resources.uniq!
    gsub_file(
      kustomization_path,
      /resources:\n(  [#-].+\n)+/,
      "resources:\n#{existing_resources.sort.map { |resource| "  - #{resource}" }.join("\n")}\n"
    )
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

    def aqueduct_folder
      "#{kustomize_folder_for_environment}/aqueduct"
    end

    def aqueduct_deployments_folder
      "#{aqueduct_folder}/deployments"
    end

    def generate_kubernetes_config_from_kustomize
      in_root do
        run "gh kustomize build"
      end
    end
  end

end
