# typed: false
# frozen_string_literal: true

class HydroProcessorGenerator < Rails::Generators::NamedBase
  source_root File.expand_path("templates", __dir__)

  class_option :dead_letter, type: :boolean, default: false,
    desc: "Whether or not a Dead Letter Topic is configured for this Hydro processor"
  class_option :topic, type: :string, required: true,
    desc: "The Hydro topic that this processor will subscribe to"
  class_option :transient_error_resiliency, type: :boolean, default: false,
    desc: "Whether or not to include resiliency for transient errors so that processors retry and eventually pause when allow-listed transient errors are encountered"
  class_option :batching, type: :boolean, default: false,
    desc: "Whether or not this processor will process messages in batches (as opposed to individually)."

  def generate_hydro_processor_class
    constants = class_name.split("::")
    constants.each_with_index do |constant, level|
      file_name = level.zero? ? "lib/github/stream_processors.rb" : "lib/github/stream_processors/#{constants.take(level).map(&:underscore).join("/")}.rb"
      module_name = level.zero? ? "StreamProcessors" : constants[level - 1]

      ensure_namespaced_file_exists(file_name, constants.take(level))
      inject_into_module file_name, module_name do
        "autoload :#{constant}, \"github/stream_processors/#{constants.take(level + 1).map(&:underscore).join("/")}\"\n".indent(2 * (2 + level))
      end
      sort_autoloads(File.join(destination_root, file_name))
    end

    ensure_namespaced_file_exists("lib/github/stream_processors/#{file_path}.rb", constants, type: :class)
    processor_class_contents = ERB.new(File.read(File.join(File.dirname(__FILE__), "templates", "hydro_processor.rb.erb")), trim_mode: "-").result(binding)
    indented_processor_class_contents = processor_class_contents.lines.map { |line| line.indent(2 * (2 + constants.size)) }.join
    inject_into_class "lib/github/stream_processors/#{file_path}.rb", constants.last, indented_processor_class_contents

    if options[:batching]
      gsub_file "lib/github/stream_processors/#{file_path}.rb", /(class #{constants.last})/, '\1 < BatchedMessageProcessor'
    else
      gsub_file "lib/github/stream_processors/#{file_path}.rb", /(class #{constants.last})/, '\1 < SingleMessageProcessor'
    end
  end

  def generate_hydro_processor_test
    template "hydro_processor_test.rb.erb", "test/lib/github/stream_processors/#{file_path}_test.rb"
  end

  def generate_entrypoint_script
    template "script.rb.erb", "script/#{dashed_name}"
    chmod "script/#{dashed_name}", 0755
  end

  def generate_kubernetes_deployment
    template "kubernetes_deployment.yaml.erb", "config/kustomize/base/commonBase/deployments/#{dashed_name}.yaml"
    existing_resources = YAML.safe_load(File.read("config/kustomize/base/commonBase/kustomization.yaml")).dig("resources")
    existing_resources.push("deployments/#{dashed_name}.yaml")
    existing_resources.uniq!
    gsub_file(
      "config/kustomize/base/commonBase/kustomization.yaml",
      /resources:.*/m,
      "resources:\n#{existing_resources.sort.map { |resource| "  - #{resource}" }.join("\n")}\n"
    )
    generate_kubernetes_config
  end

  def seed_topic_in_kafka_lite_server
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

  no_commands do
    def dashed_name
      (class_path + [file_name]).join("-").dasherize
    end

    def group_id
      "github-\#{Rails.env}-#{class_name.underscore.gsub(/\//, "-")}"
    end

    def ensure_namespaced_file_exists(file_name, constants, type: :module)
      return if File.exist?(File.join(destination_root, file_name))

      create_file(file_name, <<~RB)
      # typed: true
      # frozen_string_literal: true

      module GitHub
        module StreamProcessors
      #{constants.map.with_index { |constant, level| "#{type == :module || level < constants.size - 1 ? "module" : "class" } #{constant}".indent(2 * (2 + level)) }.join("\n")}
      #{constants.size.times.reverse_each.map { |level| "end".indent(2 * (2 + level)) }.join("\n")}
        end
      end
      RB
    end

    def sort_autoloads(path)
      lines = File.read(path).lines
      sorted_lines = []
      autoload_lines = []
      lines.each do |line|
        if !line.starts_with?(/\A    autoload/)
          if autoload_lines.any?
            sorted_lines.push(*autoload_lines.sort)
            autoload_lines = []
          end

          sorted_lines.push(line)
        else
          autoload_lines.push(line)
        end
      end

      File.write(path, sorted_lines.join)
    end

    def generate_kubernetes_config
      in_root do
        run "gh kustomize build"
      end
    end
  end
end
