# typed: true
# frozen_string_literal: true

class TwirpGenerator < Rails::Generators::Base
  source_root File.expand_path("templates", __dir__)

  class_option :from_gem, type: :string, required: true, desc: "Gem to use. Must match naming pattern: monolith-twirp-<namespace>-<name>"
  class_option :client, type: :string, desc: "Client identifier that can access generated handler. Defaults to the namespace."
  class_option :version, type: :string, desc: "Version to generate. Defaults to all versions."
  class_option :service, type: :string, desc: "Service to generate. Defaults to all services."

  def validate_gem
    unless @options[:from_gem] =~ /\Amonolith-twirp-[a-z_]+-[a-z_]+\Z/
      abort "Gem name must match pattern: monolith-twirp-<namespace>-<name>"
    end
    require @options[:from_gem]

    version = @options[:version].to_sym if @options[:version]

    parts = @options[:from_gem].split("-")
    @twirp_module = TwirpModule.new(
      *parts[2..-1],
      client: @options[:client],
      version_name: version,
      service_name: @options[:service]
    )

    versions = @twirp_module.versions
    if versions.empty?
      raise ArgumentError, "Could not find any version constants (e.g. V1) for gem: #{@options[:from_gem]}" +
        "\nConstants found: #{@twirp_module.definitions.map(&:name)}"
    end
  rescue LoadError
    raise ArgumentError, "Unknown gem: #{@options[:from_gem]}"
  rescue NameError
    raise ArgumentError, "Could not process gem: #{@options[:from_gem]}"
  end

  def generate_handlers
    @twirp_module.versions.each do |version|
      @current_version = version
      version.services.each do |service|
        @current_service = service
        template "handler.rb.erb", service.handler_filename
      end
    end
  end

  def generate_integration_tests
    @twirp_module.versions.each do |version|
      @current_version = version
      version.services.each do |service|
        @current_service = service
        service.rpcs.each do |rpc|
          @current_rpc = rpc
          template "integration_test.rb.erb", rpc.integration_test_filename
        end
      end
    end
  end

  def insert_mountings
    @twirp_module.versions.each do |version|
      version.services.each do |service|
        inject_into_file "app/api/internal/twirp.rb", %Q(  mount ::#{service.handler_name}\n), after: %Q(mount ::Api::Internal::Twirp::Examples::Octocat::V1::OctocatAPIHandler\n)
      end
    end
  end

  def insert_api_inflections
    @twirp_module.versions.each do |version|
      version.services.each do |service|
        without_extension = File.basename(service.handler_filename, ".rb")
        inject_into_file "lib/github/zeitwerk_inflector.rb",
          %Q(      "#{without_extension}" => "#{service.handler_short_name}",\n),
          after: %Q("octocat_api_handler" => "OctocatAPIHandler",\n)
      end
    end
  end

  class TwirpModule
    attr_reader :namespace, :name, :client, :version_name, :service_name
    def initialize(namespace, name, client:, version_name:, service_name:)
      @namespace = namespace
      @name = name
      @client = client || namespace
      @version_name = version_name
      @service_name = service_name
    end

    def definitions
      return @definitions if defined?(@definitions)
      namespace_modules = find_constants(MonolithTwirp, @namespace)
      @definitions = namespace_modules.flat_map do |namespace_module|
        find_constants(namespace_module, @name)
      end
    end

    def versions
      @versions ||= begin

        versions = definitions.flat_map do |definition|
          definition.constants.grep(/\AV\d+\Z/).map do |name|
            Version.new(self, name, definition.const_get(name), service_name)
          end
        end

        if version_name
          version = versions.find { |v| v.name == version_name }
          unless version
            raise ArgumentError, "Unknown version: #{version_name}, available versions: #{versions.map { |v| v.name.to_s }}"
          end
          [version]
        else
          versions
        end
      end
    end

    private

    # Get all constants matching a name, normalizing any camelization and snake casing
    def find_constants(base, name)
      normalized = name.upcase.delete("_")
      base.constants.select { |c| c.to_s.upcase == normalized }.map do |const|
        base.const_get(const)
      end
    end
  end

  class Version
    attr_reader :name, :definition, :service_name
    def initialize(twirp_module, name, definition, service_name)
      @twirp_module = twirp_module
      @name = name
      @definition = definition
      @service_name = service_name
    end

    def services
      @services ||= begin
        services = definition.constants.grep(/APIService\Z/).map do |name|
          Service.new(@twirp_module, self, name)
        end

        if service_name
          service = services.find { |s| s.short_name == service_name }
          unless service
            raise ArgumentError, "Unknown service: #{service_name}, available versions: #{services.map(&:short_name)}"
          end
          [service]
        else
          services
        end
      end
    end

    def modules
      @modules ||= /\AMonolithTwirp::(?<twirp_namespace>.+?)::(?<twirp_module>.+?)::(?<version>.+?)\Z/.match(definition.name)
    end
  end

  class Service
    def initialize(twirp_module, version, name)
      @twirp_module = twirp_module
      @version = version
      @name = name
    end

    def definition
      @definition ||= @version.definition.const_get(@name)
    end

    def rpcs
      @rpcs ||= begin
        definition.rpcs.map do |name, config|
          RPC.new(@twirp_module, @version, self, name, config)
        end
      end
    end

    def handler_filename
      @handler_filename ||= begin
        without_service = @name.to_s.underscore.sub(/_service\Z/, "")
        "app/api/internal/twirp/#{@twirp_module.namespace}/#{@twirp_module.name}/#{@version.name.to_s.downcase}/#{without_service}_handler.rb"
      end
    end

    def handler_name
      @handler_name ||= begin
        "Api::Internal::Twirp::#{@version.modules[:twirp_namespace]}::#{@version.modules[:twirp_module]}::#{@version.modules[:version]}::#{handler_short_name}"
      end
    end

    def short_name
      @short_name ||= @name.to_s.sub(/Service\Z/, "")
    end

    def handler_short_name
      @handler_short_name ||= @name.to_s.sub(/Service\Z/, "") << "Handler"
    end
  end

  class RPC
    attr_reader :name
    def initialize(twirp_module, version, service, name, config)
      @twirp_module = twirp_module
      @version = version
      @service = service
      @name = name
      @config = config
    end

    def handler_method
      @config[:ruby_method]
    end

    def input_class
      @config[:input_class]
    end

    def output_class
      @config[:output_class]
    end

    def integration_test_filename
      @integration_test_filename ||= begin
        handler_name = File.basename(@service.handler_filename, ".rb")
        "test/integration/api/internal/twirp/#{@twirp_module.namespace}/#{@twirp_module.name}/#{@version.name.to_s.downcase}/#{handler_name}/#{handler_method}_test.rb"
      end
    end
  end
end
