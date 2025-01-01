# typed: true
# frozen_string_literal: true

module GitHub
  # Manages the "runtime environment": either 'dotcom' or 'enterprise'. The
  # GitHub::Runtime class can be used to switch between the two runtime modes
  # in development environments and is also used to determine current mode in
  # production environments.
  #
  # NOTE This file is loaded as part of the config/basic.rb lightweight environment.
  # Do not add any additional library requires here.
  class Runtime
    # Is it possible to dynamically switch from dotcom to enterprise and visa
    # versa in this process. The flag is set by the development server and is
    # typically not available otherwise.
    def switchable?
      !ENV["GH_RUNTIME_SWITCHABLE"].to_s.empty?
    end

    # The current runtime environment. This is always the environment that this
    # process is running under right now. It never changes without the server
    # being restarted.
    #
    # Returns 'dotcom' or 'enterprise'.
    def current
      @current ||=
        if switchable? && File.exist?(current_runtime_path)
          File.read(current_runtime_path).chomp
        else
          current_from_environment
        end
    end

    # The pending runtime environment. This is set
    #
    # Returns nil when no environment change is pending, or 'github' or
    # 'enterprise' when a different environment has been requested.
    def pending
      if File.exist?(pending_runtime_path)
        File.read(pending_runtime_path).chomp
      end
    end

    # Is a runtime switch currently pending?
    def pending?
      !pending.nil?
    end

    # Is the current runtime mode set to dotcom?
    def dotcom?
      current == "dotcom"
    end

    # Is the current runtime mode set to enterprise?
    def enterprise?
      current == "enterprise"
    end

    # The opposite runtime of whatever we're currently running under.
    # 'enterprise' when running under 'dotcom' and vise versa.
    def opposite_runtime
      current == "dotcom" ? "enterprise" : "dotcom"
    end

    # Initiate the switch from the current runtime mode to a different one.
    # This just writes the pending file and restarts the server. The actual
    # setup process is run after the server is restarted.
    #
    # env - The name of the environment to switch to. Must be either
    #       'dotcom' or 'enterprise'.
    #
    # Returns true when a switch was put in motion, or falsey when the requested
    # environment is already running.
    def switch(env)
      require "fileutils"

      if !%w(enterprise dotcom).include?(env)
        raise ArgumentError, "unknown runtime environment: #{env.inspect}"
      end

      if current != env
        FileUtils.mkdir_p File.dirname(pending_runtime_path)
        File.open(pending_runtime_path, "wb") { |f| f.puts(env) }
        restart_server_process!
        true
      end
    end

    # Run when the new server process is started. The pending runtime file is
    # the new runtime mode. The script/setup utility is used to perform the
    # actual switch.
    def perform_pending_setup
      if pending? && pending != current
        if !system("script/setup")
          fail "Setup failed"
        end
      end
    end

    # Signals the currently running unicorn server process with QUIT so it will
    # be restarted. This is called after the pending runtime file is written.
    # When the server starts back up, the new environment is bootstrapped and
    # initialized as needed.
    def restart_server_process!
      Process.kill "QUIT", $$
    end

    # The path to the currently running runtime file. This determine what
    # environment the server will boot into.
    def current_runtime_path
      "#{GitHub::AppEnvironment.root}/tmp/runtime/current"
    end

    # The path to the requested new runtime environment. This file is detected
    def pending_runtime_path
      "#{GitHub::AppEnvironment.root}/tmp/runtime/pending"
    end

    # Determine the current runtime name from the environment. This basically
    # looks for the enterprise environ vars. If none are present, the normal
    # dotcom environment is assumed.
    def current_from_environment
      if enterprise_environment?
        "enterprise"
      else
        "dotcom"
      end
    end

    ENABLED_VALUES = %w(1 true)

    # Are any of the supported enterprise mode environment variables set?
    def enterprise_environment?
      %w(ENTERPRISE E FI).any? { |var| ENABLED_VALUES.include?(ENV[var]) }
    end

    # Is multi-tenant environment variable set?
    def multi_tenant_enterprise_environment?
      return false if enterprise_environment?
      ENABLED_VALUES.include?(ENV["MULTI_TENANT_ENTERPRISE"])
    end

    # Rack Middleware that intercepts requests that include a ?_runtime=<env>
    # query string param and switch the active runtime environment. The
    # middleware just writes the requested new runtime to a file and forces a
    # server restart. The environment bootstrap and setup takes place when the
    # new server process starts up and detects a requested switch.
    class Switcher
      PARAM = "_runtime"
      GET   = /#{PARAM}=\?/
      SET   = /#{PARAM}=(enterprise|dotcom)/

      def initialize(app)
        @app = app
      end

      # The GitHub::Runtime object interface.
      def runtime
        ::GitHub.runtime
      end

      # Process the request. Care should be taken to keep this fast when no
      # _runtime query param is present.
      def call(env)
        requested_runtime = env["QUERY_STRING"][SET, 1]

        if requested_runtime && runtime.current != requested_runtime
          runtime.switch(requested_runtime)
          request = Rack::Request.new(env)
          url = request.url.gsub("#{PARAM}=#{requested_runtime}", "")
          [200, { "Content-Type" => "text/html" }, [template(url)]]

        elsif env["QUERY_STRING"] =~ GET
          [200, { "Content-Type" => "text/plain" }, [runtime.current]]

        else
          @app.call(env)
        end
      end

      # Render the runtime switch in progress template.
      #
      # url - The URL to redirect to when switching is complete.
      #
      # Returns a string HTML body.
      def template(url)
        File.read("#{GitHub::AppEnvironment.root}/public/switching_runtime.html").
          gsub("{{url}}", url)
      end
    end

  end
end
