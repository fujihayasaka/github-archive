module GhConfig
  # Boolean attribute specifying whether the site is in SSL mode. This is
  # typically set true explicitly in production environments.
  #
  # Returns true if SSL is enabled for the site, false otherwise.
  def ssl?
    @ssl ||= ENV['GH_SSL']
  end
  attr_writer :ssl
  alias ssl ssl?

  # Determine if the app is runing in Enterprise mode.
  #
  # Returns true if running under Enterprise, else false.
  def enterprise?
    @enterprise ||= !String(ENV['ENTERPRISE']).empty?
  end
  attr_writer :enterprise

  ##
  # Host Names

  # The main external GitHub hostname only. No http:// prefix or protocol
  # information is included.
  #
  # Returns the hostname string ("github.com", "github.dev", etc.) or nil if
  # no host_name has been set.
  def host_name
    @host_name || ENV['GH_HOSTNAME']
  end
  attr_writer :host_name

  # Returns http:// or https:// depending on #ssl attribute value
  def url
    @url ||= ssl? ? https_url : http_url
  end
  attr_writer :url

  def host
    @host ||= ssl? ? https_host : http_host
  end

  def http_host
    "http://#{host_name}"
  end

  def https_host
    "https://#{host_name}"
  end

  def http_url
    @http_url ||= "#{http_host}#{application_url if hosted?}".freeze
  end
  attr_writer :http_url

  def https_url
    @https_url ||= "#{https_host}#{application_url if hosted?}".freeze
  end
  attr_writer :https_url

  # If #hosted? is false, this is added
  # to host_name to form the URL
  def application_url
    @application_url ||= ""
  end
  attr_writer :application_url

  # Get the relative path compontent
  def application_path
    @application_path ||= "#{application_url if hosted?}/"
  end
  attr_writer :application_path

  # Is the application hosted on its own hosted?
  def hosted?
    @hosted ||= true
  end
  attr_writer :hosted

  def root
    defined?(Rails) ? Rails.root : ENV['RACK_ROOT']
  end

  # reload the config.yml values and set each config attribute
  def reload_config
    import_yaml_config "#{root}/config.yml"
  end

  # Imports config values from the YAML file specified into the current
  # config. The config file may include values for any attributes defined in
  # this module.
  #
  # file - The string path to the YAML file to load.
  #
  # Returns nothing.
  # Raises RuntimeError when the config file includes an unknown key.
  #
  # Examples:
  #   The following YAML file would cause the ssl config attribute to be set
  #   true and the host_name attribute to be set to "github.apple.com":
  #
  #   ssl:       true
  #   host_name: github.apple.com
  def import_yaml_config(file)
    load_yaml_config(file).each do |key, value|
      if respond_to?("#{key}=")
        __send__("#{key}=", value)
      else
        fail "unknown config value: #{key.inspect}"
      end
    end
  end

  # Load a YAML file if it exists and return its deserialized contents.
  #
  # Returns a Hash of config values.
  def load_yaml_config(file)
    if !test? && File.exist?(file)
      require 'yaml'
      YAML.load_file(file)
    else
      {}
    end
  end

  def test?
    defined?(Rails) ? Rails.test? : ENV['RACK_ENV'] == 'test'
  end

  def oauth_client_id
    @oauth_client_id ||= ENV['GITHUB_CLIENT_ID']
  end
  attr_writer :oauth_client_id

  def oauth_client_secret
    @oauth_client_secret ||= ENV['GITHUB_CLIENT_SECRET']
  end
  attr_writer :oauth_client_secret
end
