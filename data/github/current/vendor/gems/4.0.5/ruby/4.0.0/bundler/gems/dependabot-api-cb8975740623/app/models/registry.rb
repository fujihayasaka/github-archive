# frozen_string_literal: true

require "uri"

# Registry is a private registry configuration.
# Parsed from `registries:` entry in dependabot.yaml
# Secrets are references to an external system, such as Kredz
# rubocop:disable Metrics/ClassLength
class Registry < ApplicationRecord
  NAME_MAX_LENGTH = 64
  TOKEN_SPACER = ":"

  TYPES_FOR_PACKAGE_MANAGER = {
    "bazel" => %w(git_source).freeze,
    "bundler" => %w(rubygems_server git_source).freeze,
    "devcontainers" => %w(git_source).freeze,
    "docker" => %w(docker_registry git_source).freeze,
    "docker_compose" => %w(docker_registry git_source).freeze,
    "dotnet_sdk" => %w().freeze,
    "npm_and_yarn" => %w(npm_registry git_source).freeze,
    "bun" => %w(npm_registry git_source).freeze,
    "pip" => %w(python_index git_source).freeze,
    "composer" => %w(composer_repository git_source).freeze,
    "helm" => %w(docker_registry git_source helm_registry).freeze,
    "hex" => %w(hex_organization hex_repository git_source).freeze,
    "submodules" => %w(git_source).freeze,
    "cargo" => %w(cargo_registry git_source).freeze,
    "gradle" => %w(maven_repository git_source).freeze,
    "github_actions" => %w(git_source).freeze,
    "go_modules" => %w(git_source goproxy_server).freeze,
    "elm" => %w(git_source).freeze,
    "terraform" => %w(git_source terraform_registry).freeze,
    "nuget" => %w(nuget_feed git_source).freeze,
    "maven" => %w(maven_repository git_source).freeze,
    "opentofu" => %w(git_source).freeze,
    "pub" => %w(pub_repository git_source).freeze,
    "rust_toolchain" => %w().freeze,
    "sbt" => %w(maven_repository git_source).freeze,
    "swift" => %w(git_source).freeze,
    "uv" => %w(python_index git_source).freeze,
    "vcpkg" => %w(git_source).freeze,
    "conda" => %w(python_index git_source).freeze,
    "deno" => %w(npm_registry git_source).freeze,
    "julia" => %w(git_source).freeze,
    "nix" => %w(git_source).freeze,
    "pre_commit" => %w(git_source).freeze,
  }.freeze

  belongs_to :source, polymorphic: true

  has_many :update_configs, through: :repos, inverse_of: :registries

  validates :name, presence: true
  validates :credentials, presence: true
  validates :registry_type,
            presence: true,
            inclusion: { in: TYPES_FOR_PACKAGE_MANAGER.values.flatten }
  validates :source_type, inclusion: { in: %w(Repo Account) }

  validate :credentials_are_small
  validate :credentials_are_valid_json_object
  validate :credentials_do_not_mix_deprecated_and_canonical_keys
  validate :credentials_are_allowed_for_registry_type
  validate :name_is_unique

  scope :for_package_manager,
        ->(pm) { where(registry_type: TYPES_FOR_PACKAGE_MANAGER.fetch(pm)) }

  # credentials passed to the proxy container
  def serialized_credentials # rubocop:disable Metrics/AbcSize,Metrics/MethodLength,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    credentials = case registry_type
                  when "cargo_registry"
                    base_creds = {
                      "type" => registry_type,
                      "url" => parsed_credentials["url"],
                    }
                    # Only add token if not using OIDC
                    base_creds["token"] = parsed_credentials["token"] unless oidc_credentials?
                    base_creds.merge(parsed_credentials.except("url", "token"))
                  when "composer_repository", "docker_registry", "helm_registry"
                    base_creds = {
                      "type" => registry_type,
                      "registry" => host_from_url(parsed_credentials["url"]),
                    }
                    # JFrog OIDC requires the url to be passed along
                    base_creds["url"] = parsed_credentials["url"] if jfrog_oidc_credentials?
                    base_creds.merge(parsed_credentials.except("url"))
                  when "git_source"
                    {
                      "type" => registry_type,
                      "host" => host_from_url(parsed_credentials["url"]),
                    }.merge(parsed_credentials.except("url"))
                  when "hex_organization"
                    base_creds = {
                      "type" => registry_type,
                    }
                    # Only add token if not using OIDC
                    base_creds["token"] = parsed_credentials["key"] unless oidc_credentials?
                    base_creds.merge(parsed_credentials.except("key"))
                  when "hex_repository"
                    {
                      "url" => host_from_url(parsed_credentials["url"]),
                      "type" => registry_type,
                      "auth-key" => parsed_credentials["auth-key"],
                    }.merge(parsed_credentials.except("url"))
                  when "npm_registry"
                    base_creds = {
                      "type" => registry_type,
                      "registry" => host_path_from_url(parsed_credentials["url"]),
                    }
                    # if using JFrog OIDC pass along the url, if not using OIDC create the token
                    if oidc_credentials?
                      base_creds["url"] = parsed_credentials["url"] if jfrog_oidc_credentials?
                    else
                      base_creds["token"] = token_from_token_or_username_and_password
                    end
                    base_creds.merge(parsed_credentials.except("url", "token", "username", "password"))
                  when "nuget_feed"
                    base_creds = {
                      "type" => registry_type,
                    }
                    # Only add token if not using OIDC
                    base_creds.merge!(nuget_credentials_from_token_or_username_and_password) unless oidc_credentials?
                    base_creds.merge(parsed_credentials.except("token", "username", "password"))
                  when "python_index"
                    base_creds = {
                      "type" => registry_type,
                      "index-url" => parsed_credentials["url"],
                    }
                    # if using JFrog OIDC pass along the url, if not using OIDC create the token
                    if oidc_credentials?
                      base_creds["url"] = parsed_credentials["url"] if jfrog_oidc_credentials?
                    else
                      base_creds["token"] = token_from_token_or_username_and_password
                    end
                    base_creds.merge(parsed_credentials.except("url", "token", "username", "password"))
                  when "rubygems_server"
                    base_creds = {
                      "type" => registry_type,
                      "host" => host_from_url(parsed_credentials["url"]),
                    }
                    # if using JFrog OIDC pass along the url, if not using OIDC create the token
                    if oidc_credentials?
                      base_creds["url"] = parsed_credentials["url"] if jfrog_oidc_credentials?
                    else
                      base_creds["token"] = token_from_token_or_username_and_password
                    end
                    base_creds.merge(parsed_credentials.except("url", "token", "username", "password"))
                  when "terraform_registry"
                    base_creds = {
                      "type" => registry_type,
                      "host" => host_from_url(parsed_credentials["url"]),
                    }
                    # if using JFrog OIDC pass along the url, if not using OIDC pass along the token
                    if oidc_credentials?
                      base_creds["url"] = parsed_credentials["url"] if jfrog_oidc_credentials?
                    else
                      base_creds["token"] = parsed_credentials["token"]
                    end
                    base_creds.merge(parsed_credentials.except("url", "token"))
                  when "goproxy_server"
                    base_creds = {
                      "type" => registry_type,
                      "url" => parsed_credentials["url"],
                    }
                    # Only add username/password if not using OIDC
                    unless oidc_credentials?
                      base_creds["username"] = parsed_credentials["username"]
                      base_creds["password"] = parsed_credentials["password"]
                    end
                    base_creds.merge(parsed_credentials.except("url", "username", "password"))
                  else
                    { "type" => registry_type }.merge(parsed_credentials)
                  end

    credentials.merge(serialized_credential_metadata)
  end

  # metadata passed to the updater. Should *NOT* contain sensitive information
  def serialized_credential_metadata
    metadata = { "type" => registry_type }.merge(key_name => key)

    metadata["replaces-base"] = parsed_credentials["replaces-base"] if parsed_credentials.key?("replaces-base")

    metadata["public-key-fingerprint"] = parsed_credentials["public-key-fingerprint"] if uses_hex_repository_public_key?
    metadata["repo"] = parsed_credentials["repo"] if parsed_credentials.key?("repo")
    metadata["registry"] = parsed_credentials["registry"] if uses_cargo_registry_key?

    metadata
  end

  def key_name
    registry_keys = {
      "git_source" => "host",
      "rubygems_server" => "host",
      "docker_registry" => "registry",
      "helm_registry" => "registry",
      "npm_registry" => "registry",
      "composer_repository" => "registry",
      "python_index" => "index-url",
      "php_environment_variable" => "env-key",
      "maven_repository" => "url",
      "nuget_feed" => "url",
      "hex_organization" => "organization",
      "hex_repository" => "url",
      "terraform_registry" => "host",
      "pub_repository" => "url",
      "cargo_registry" => "url",
      "goproxy_server" => "url",
    }
    registry_keys[registry_type]
  end

  def key
    return unless key_name

    case registry_type
    when "composer_repository", "docker_registry", "git_source", "rubygems_server", "terraform_registry",
      "helm_registry"
      host_from_url(parsed_credentials["url"])
    when "npm_registry"
      host_path_from_url(parsed_credentials["url"])
    when "python_index"
      parsed_credentials["url"]
    else
      parsed_credentials.fetch(key_name)
    end
  end

  def credentials_are_allowed_for_registry_type # rubocop:disable Metrics/CyclomaticComplexity
    return unless credentials_are_valid_json_object

    case registry_type
    when "cargo_registry" then cargo_credentials_check
    when "composer_repository" then composer_credentials_check
    when "docker_registry" then docker_credentials_check
    when "helm_registry" then helm_credentials_check
    when "git_source" then git_source_credentials_check
    when "hex_organization" then hex_organization_credentials_check
    when "hex_repository" then hex_repository_credentials_check
    when "maven_repository" then maven_repository_credentials_check
    when "npm_registry" then javascript_credentials_check
    when "nuget_feed" then nuget_feed_credentials_check
    when "pub_repository" then pub_repository_credentials_check
    when "python_index" then pip_credentials_check
    when "rubygems_server" then bundler_credentials_check
    when "terraform_registry" then terraform_credentials_check
    when "goproxy_server" then go_proxy_credentials_check
    end
  end

  private

  def parsed_credentials
    @parsed_credentials ||= normalize_deprecated_credential_keys(JSON.parse(credentials))
  end

  # Mapping of deprecated credential key names to their canonical equivalents.
  DEPRECATED_CREDENTIAL_KEYS = {
    "oidc-namespace" => "namespace",
    "oidc-service-slug" => "service-slug",
    "oidc-audience" => "audience",
  }.freeze

  # Normalizes deprecated credential key names to their canonical form.
  def normalize_deprecated_credential_keys(creds)
    return creds unless creds

    DEPRECATED_CREDENTIAL_KEYS.each do |old_key, new_key|
      next unless creds.key?(old_key)

      creds[new_key] = creds.delete(old_key) unless creds.key?(new_key)
    end
    creds
  end

  def host_from_url(url)
    uri = parse_uri(url)
    host_from_parsed(uri)
  end

  def host_from_parsed(uri)
    if uri.port != uri.default_port
      "#{uri.host}:#{uri.port}"
    else
      uri.host
    end
  end

  def host_path_from_url(url)
    uri = parse_uri(url)
    host = host_from_parsed(uri)
    return host if uri.path.blank? || uri.path == "/"

    "#{host}#{uri.path}"
  end

  def parse_uri(url)
    uri = URI.parse(url)
    return uri unless uri.scheme.nil? || uri.host.nil?

    URI.parse("https://#{url}")
  end

  def token_from_token_or_username_and_password
    token = parsed_credentials["token"]
    return token if token

    "#{parsed_credentials['username']}#{TOKEN_SPACER}#{parsed_credentials['password']}"
  end

  def nuget_credentials_from_token_or_username_and_password
    return {} if token_from_token_or_username_and_password == TOKEN_SPACER

    {
      "token" => token_from_token_or_username_and_password,
    }
  end

  def credentials_are_small
    return true unless credentials.length > 3000

    errors.add(:credentials, "must not be longer than 3,000 characters")
    false
  end

  def credentials_are_valid_json_object
    return unless credentials_are_small
    return true if parsed_credentials.is_a?(Hash)

    errors.add(:credentials, "must be a JSON object")
    false
  rescue JSON::ParserError
    errors.add(:credentials, "must be valid JSON")
    false
  end

  def credentials_do_not_mix_deprecated_and_canonical_keys
    return unless parsed_credentials.is_a?(Hash)

    raw_creds = JSON.parse(credentials)
    DEPRECATED_CREDENTIAL_KEYS.each do |old_key, new_key|
      if raw_creds.key?(old_key) && raw_creds.key?(new_key)
        errors.add(:credentials, "must not contain both \"#{old_key}\" and \"#{new_key}\"")
      end
    end
  rescue JSON::ParserError
    nil
  end

  def name_is_unique
    case source
    when Repo
      name_not_in_account(source.account)
      name_not_in_repo(source)
    when Account
      name_not_in_account(source)
      source.repos.find { |r| name_not_in_repo(r) }
    end
  end

  def name_not_in_account(account)
    return true unless account.registries.
                       where(name: name).
                       where.not(id: id).
                       any?

    msg = "A registry named #{name} already "\
          "exists for #{account.github_login}"
    errors.add(:base, msg)
  end

  def name_not_in_repo(repo)
    return true unless repo.registries.
                       where(name: name).
                       where.not(id: id).
                       any?

    msg = "A registry named #{name} already "\
          "exists for #{repo.full_name}"
    errors.add(:base, msg)
  end

  def uses_hex_repository_public_key?
    parsed_credentials.key?("public-key-fingerprint")
  end

  def uses_cargo_registry_key?
    registry_type == "cargo_registry" && parsed_credentials.key?("registry")
  end

  def git_source_credentials_check
    validate_has_attribute("url")
    validate_git_repo_format
    validate_has_username_and_password
    validate_github_secret_format("password")
  end

  def bundler_credentials_check
    validate_has_attribute("url")
    validate_rubygems_url_format

    # Support OIDC OR traditional auth
    if oidc_credentials?
      validate_oidc_credentials
      validate_does_not_have_attribute("token")
      validate_does_not_have_attribute("username")
      validate_does_not_have_attribute("password")
    else
      validate_not_oidc_credentials
      validate_has_username_and_password_or_token
      validate_gemfury_secret_not_in("url")
      validate_basic_auth_credentials_not_in("url")
      validate_github_secret_format("token")
    end
  end

  def docker_credentials_check
    validate_has_attribute("url")
    validate_docker_registry_format

    # Support OIDC OR traditional auth
    if oidc_credentials?
      validate_oidc_credentials
      validate_does_not_have_attribute("username")
      validate_does_not_have_attribute("password")
    else
      validate_not_oidc_credentials
      validate_has_username_and_password
      validate_not_quoted("username")
      validate_not_quoted("password")
      validate_usename_for_google_container_registry
    end
  end

  def helm_credentials_check
    validate_has_attribute("url")
    validate_helm_registry_format

    # Support OIDC OR traditional auth
    if oidc_credentials?
      validate_oidc_credentials
      validate_does_not_have_attribute("username")
      validate_does_not_have_attribute("password")
    else
      validate_not_oidc_credentials
      validate_has_username_and_password
      validate_not_quoted("username")
      validate_not_quoted("password")
    end
  end

  def javascript_credentials_check
    validate_has_attribute("url")
    validate_javascript_registry_format
    validate_gemfury_secret_not_in("url")
    validate_basic_auth_credentials_not_in("url")

    # Support OIDC OR traditional auth
    if oidc_credentials?
      validate_oidc_credentials
    else
      validate_has_username_and_password_or_token
      validate_not_oidc_credentials
      validate_not_quoted("token")
      validate_not_quoted("password")
      validate_not_base64_basic("token")
      validate_github_secret_format("token")
      validate_github_secret_format("password")
    end
  end

  def pip_credentials_check
    validate_has_attribute("url")
    validate_is_url("url")
    validate_gemfury_secret_not_in("url")
    validate_basic_auth_credentials_not_in("url")

    # Support OIDC OR traditional auth
    if oidc_credentials?
      validate_oidc_credentials
    else
      validate_has_username_and_password_if_has_either
      validate_not_oidc_credentials
      validate_not_quoted("token")
      validate_not_quoted("password")
      validate_github_secret_format("token")
      validate_github_secret_format("password")
    end
  end

  def composer_credentials_check
    validate_has_attribute("url")
    validate_composer_url_format
    validate_gemfury_secret_not_in("url")
    validate_basic_auth_credentials_not_in("url")

    # Support OIDC OR traditional auth
    if oidc_credentials?
      validate_oidc_credentials
    else
      validate_not_oidc_credentials
      validate_has_username_and_password_or_token
      if parsed_credentials["token"] && !(parsed_credentials["username"] || parsed_credentials["password"])
        validate_not_quoted("token")
        validate_github_secret_format("token")
      else
        validate_not_quoted("username")
        validate_not_quoted("password")
        validate_github_secret_format("password")
      end
    end
  end

  def maven_repository_credentials_check
    validate_has_attribute("url")
    validate_is_url("url")
    validate_basic_auth_credentials_not_in("url")

    # Support OIDC OR traditional auth
    if oidc_credentials?
      validate_oidc_credentials
    else
      validate_has_username_and_password_if_has_either
      validate_not_oidc_credentials
      validate_not_quoted("username")
      validate_not_quoted("password")
    end
  end

  def nuget_feed_credentials_check
    validate_has_attribute("url")
    validate_is_url("url")
    validate_gemfury_secret_not_in("url")
    validate_basic_auth_credentials_not_in("url")

    # Support OIDC OR traditional auth
    if oidc_credentials?
      validate_oidc_credentials
    else
      validate_has_username_and_password_if_has_either
      validate_not_oidc_credentials
      validate_not_base64_basic("token")
      validate_github_secret_format("token")
      validate_not_base64_basic("password")
      validate_github_secret_format("password")
    end
  end

  def hex_organization_credentials_check
    validate_has_attribute("organization")
    validate_has_attribute("key")
    validate_github_secret_format("key")
  end

  def hex_repository_credentials_check
    validate_has_attribute("url")
    validate_is_url("url")
    validate_has_attribute("repo")
    if oidc_credentials?
      validate_oidc_credentials
      validate_does_not_have_attribute("auth-key")
    else
      validate_not_oidc_credentials
      validate_has_attribute("auth-key")
      validate_github_secret_format("auth-key")
    end
  end

  def terraform_credentials_check
    validate_has_attribute("url")
    validate_is_url("url")

    # Support OIDC OR traditional auth
    if oidc_credentials?
      validate_oidc_credentials
      validate_does_not_have_attribute("token")
    else
      validate_not_oidc_credentials
      validate_has_attribute("token")
      validate_github_secret_format("token")
    end
  end

  def pub_repository_credentials_check
    validate_has_attribute("url")
    validate_is_url("url")

    # Support OIDC OR traditional auth
    if oidc_credentials?
      validate_oidc_credentials
      validate_does_not_have_attribute("token")
    else
      validate_not_oidc_credentials
      validate_has_attribute("token")
      validate_github_secret_format("token")
    end
  end

  def cargo_credentials_check
    validate_has_attribute("registry")
    validate_has_attribute("url")
    validate_is_url("url")

    # Support OIDC OR traditional auth
    if oidc_credentials?
      validate_oidc_credentials
    else
      validate_not_oidc_credentials
      validate_has_attribute("token")
      validate_github_secret_format("token")
    end
  end

  def go_proxy_credentials_check
    validate_has_attribute("url")
    validate_is_url("url")

    # Support OIDC OR traditional auth
    if oidc_credentials?
      validate_oidc_credentials
      validate_does_not_have_attribute("username")
      validate_does_not_have_attribute("password")
    else
      validate_not_oidc_credentials
      validate_has_username_and_password
      validate_not_quoted("username")
      validate_not_quoted("password")
    end
  end

  def validate_basic_auth_credentials_not_in(key)
    return unless parsed_credentials[key]

    value = parsed_credentials[key].strip
    return unless value.match?(/.+:.+@/)

    errors.add(:base, "Basic auth credentials should not be included in the "\
                      "URL. Instead, specify them as credentials.")
  end

  def validate_gemfury_secret_not_in(key)
    return unless parsed_credentials[key]

    value = parsed_credentials[key].strip
    return unless value.match?(%r{fury\.io/[^/]+/[^/]+}) ||
                  value.match?(%r{.+@.+fury\.io/})

    errors.add(:base, "Gemfury URLs should not include their token. Instead, "\
                      "the token should be specified as a credential.")
  end

  def validate_github_secret_format(key)
    return unless parsed_credentials[key]

    value = parsed_credentials[key].strip
    return if value.include?("${{") && value.include?("}}")

    errors.add(:base, "Tokens should be stored as a GitHub secret.")
  end

  def validate_has_attribute(attribute)
    return if parsed_credentials[attribute.to_s]

    msg = "#{registry_type.humanize} registries must specify a "\
          "#{attribute}"
    errors.add(:base, msg)
  end

  def validate_does_not_have_attribute(attribute)
    return unless parsed_credentials[attribute.to_s]

    msg = "#{registry_type.humanize} registries must not specify a "\
          "#{attribute}"
    errors.add(:base, msg)
  end

  INVALID_DOCKER_REGISTRY_URL =
    "Docker registries must specify a url in the format "\
    "like `https://registry-host.io:5000` or `https://example.dkr.ecr.region.amazonaws.com`."

  def validate_docker_registry_format
    return unless parsed_credentials["url"]

    uri = parse_uri(parsed_credentials["url"])

    unless uri.path.nil? || uri.path == "" || uri.path == "/"
      msg = "#{INVALID_DOCKER_REGISTRY_URL} Please don't include a path."
      errors.add(:base, msg)
    end
  rescue URI::InvalidURIError
    errors.add(:base, INVALID_DOCKER_REGISTRY_URL)
  end

  INVALID_HELM_REGISTRY_URL =
    "Helm registries must specify a url in the format "\
    "like `https://localhost:5000` or `https://registry.example.com/helm`."

  def validate_helm_registry_format
    return unless parsed_credentials["url"]

    parse_uri(parsed_credentials["url"])
  rescue URI::InvalidURIError
    errors.add(:base, INVALID_HELM_REGISTRY_URL)
  end

  INVALID_PHP_REGISTRY_URL =
    "PHP registries must specify a url in a "\
    "format like `https://repo.packagist.com` or `https://php.fury.io`."

  def validate_composer_url_format
    url = parsed_credentials["url"]
    return unless url

    parse_uri(parsed_credentials["url"])
  rescue URI::InvalidURIError
    errors.add(:base, INVALID_PHP_REGISTRY_URL)
  end

  INVALID_RUBY_REGISTRY_URL =
    "Ruby registries must specify a url in a "\
    "format like `https://gem.fury.io` or `https://ruby.pkg.github.com`."

  def validate_rubygems_url_format
    url = parsed_credentials["url"]
    return unless url

    validate_url_not_github(parse_uri(url))
  rescue URI::InvalidURIError
    errors.add(:base, INVALID_RUBY_REGISTRY_URL)
  end

  def validate_usename_for_google_container_registry
    return unless (username = parsed_credentials["username"])
    return unless (password = parsed_credentials["password"])
    return unless password.start_with?("gclouddockertoken:")
    return if username == "_json_key"

    msg = "To authenticate with Google Container Registry with a JSON key you "\
          "must set your username to `_json_key`."
    errors.add(:base, msg)
  end

  INVALID_JAVASCRIPT_REGISTRY_URL =
    "JavaScript registries must specify a url in a "\
    "format like `https://registry.npmjs.org` or `https://npm.pkg.github.com`."

  def validate_javascript_registry_format
    return unless parsed_credentials["url"]

    parse_uri(parsed_credentials["url"])
  rescue URI::InvalidURIError
    errors.add(:base, INVALID_JAVASCRIPT_REGISTRY_URL)
  end

  INVALID_GIT_REGISTRY_URL =
    "Git registries must specify a source in a "\
    "format like `https://github.com` or `https://gitlab.com`."

  def validate_git_repo_format
    return unless parsed_credentials["url"]

    uri = parse_uri(parsed_credentials["url"])
    unless uri.path.nil? || uri.path == "" || uri.path == "/"
      msg = "#{INVALID_GIT_REGISTRY_URL} Please don't include a path."
      errors.add(:base, msg)
    end
  rescue URI::InvalidURIError
    errors.add(:base, INVALID_GIT_REGISTRY_URL)
  end

  def validate_not_quoted(attribute_name)
    return unless (attr_value = parsed_credentials[attribute_name])
    return unless attr_value.start_with?('"')
    return unless attr_value.end_with?('"')

    msg = "The #{attribute_name} should not be wrapped in quote characters."
    errors.add(:base, msg)
  end

  def validate_not_base64_basic(attribute_name)
    return unless (attr_value = parsed_credentials[attribute_name])
    return unless Base64.decode64(attr_value).ascii_only?
    return unless Base64.decode64(attr_value).include?(":")

    msg = "The #{attribute_name} looks like Base64 encoded basic auth "\
          "details. Please provide it unencoded."
    errors.add(:base, msg)
  end

  def validate_is_url(attribute_name)
    return unless parsed_credentials[attribute_name]

    url =
      begin
        URI.parse(parsed_credentials[attribute_name])
      rescue URI::InvalidURIError
        nil
      end

    return if url && (url.is_a?(URI::HTTP) || url.is_a?(URI::HTTPS))

    msg = "URLs must be valid URLs using http or https"
    errors.add(:base, msg)
  end

  def validate_url_not_github(parsed_uri)
    host = parsed_uri.host
    return if host.ends_with?(".pkg.github.com") || host.exclude?("github.com")

    msg = "Config variables may not specify GitHub as the url"
    errors.add(:base, msg)
  end

  def validate_has_username_and_password
    return if parsed_credentials["username"] && parsed_credentials["password"]

    msg = "#{registry_type.humanize} registries must specify a "\
          "username and password"
    errors.add(:base, msg)
  end

  def validate_has_username_and_password_or_token
    return if parsed_credentials["username"] && parsed_credentials["password"] && !parsed_credentials["token"]
    return if parsed_credentials["token"] && !(parsed_credentials["username"] || parsed_credentials["password"])

    msg = "#{registry_type.humanize} registries must specify a "\
          "username and password, or a token"
    errors.add(:base, msg)
  end

  def validate_has_username_and_password_if_has_either
    return if parsed_credentials["username"] && parsed_credentials["password"]
    return if !parsed_credentials["username"] && !parsed_credentials["password"]

    msg = "If either a username or password is specifed, both must be"
    errors.add(:base, msg)
  end

  def oidc_credentials?
    azure_oidc_credentials? ||
      jfrog_oidc_credentials? ||
      aws_oidc_credentials? ||
      cloudsmith_oidc_credentials? ||
      gcp_oidc_credentials?
  end

  def azure_oidc_credentials?
    parsed_credentials["tenant-id"] && parsed_credentials["client-id"]
  end

  def jfrog_oidc_credentials?
    parsed_credentials["jfrog-oidc-provider-name"] && parsed_credentials["url"]
  end

  def aws_oidc_credentials?
    parsed_credentials["aws-region"] && parsed_credentials["account-id"] && parsed_credentials["role-name"] &&
      parsed_credentials["domain"] && parsed_credentials["domain-owner"]
  end

  def cloudsmith_oidc_credentials?
    parsed_credentials["namespace"] && parsed_credentials["service-slug"] &&
      parsed_credentials["audience"]
  end

  def gcp_oidc_credentials?
    parsed_credentials["workload-identity-provider"].present?
  end

  # rubocop:disable Metrics/MethodLength
  # rubocop:disable Metrics/AbcSize
  def validate_oidc_credentials
    if azure_oidc_credentials?
      validate_azure_oidc_credentials
      validate_not_jfrog_oidc_credentials
      validate_not_aws_oidc_credentials
      validate_not_cloudsmith_oidc_credentials
      validate_not_gcp_oidc_credentials
    elsif jfrog_oidc_credentials?
      validate_jfrog_oidc_credentials
      validate_not_azure_oidc_credentials
      validate_not_aws_oidc_credentials
      validate_not_cloudsmith_oidc_credentials
      validate_not_gcp_oidc_credentials
    elsif aws_oidc_credentials?
      validate_aws_oidc_credentials
      validate_not_azure_oidc_credentials
      validate_not_jfrog_oidc_credentials
      validate_not_cloudsmith_oidc_credentials
      validate_not_gcp_oidc_credentials
    elsif cloudsmith_oidc_credentials?
      validate_cloudsmith_oidc_credentials
      validate_not_azure_oidc_credentials
      validate_not_jfrog_oidc_credentials
      validate_not_aws_oidc_credentials
      validate_not_gcp_oidc_credentials
    elsif gcp_oidc_credentials?
      validate_gcp_oidc_credentials
      validate_not_azure_oidc_credentials
      validate_not_jfrog_oidc_credentials
      validate_not_aws_oidc_credentials
      validate_not_cloudsmith_oidc_credentials
    else
      errors.add(:base, "Unsupported OIDC credentials configuration.")
    end
  end
  # rubocop:enable Metrics/AbcSize
  # rubocop:enable Metrics/MethodLength

  def validate_not_oidc_credentials
    # azure
    validate_does_not_have_attribute("tenant-id")
    validate_does_not_have_attribute("client-id")
    # jfrog
    validate_does_not_have_attribute("jfrog-oidc-provider-name")
    # aws
    validate_does_not_have_attribute("aws-region")
    validate_does_not_have_attribute("account-id")
    validate_does_not_have_attribute("role-name")
    validate_does_not_have_attribute("domain")
    validate_does_not_have_attribute("domain-owner")
    # cloudsmith
    validate_does_not_have_attribute("namespace")
    validate_does_not_have_attribute("service-slug")
    validate_does_not_have_attribute("api-host")
    # gcp
    validate_does_not_have_attribute("workload-identity-provider")
    validate_does_not_have_attribute("service-account")
  end

  def validate_azure_oidc_credentials
    validate_has_attribute("tenant-id")
    validate_has_attribute("client-id")
    validate_not_quoted("tenant-id")
    validate_not_quoted("client-id")
    validate_github_secret_format_or_guid("tenant-id")
    validate_github_secret_format_or_guid("client-id")

    validate_does_not_have_attribute("token")
    validate_does_not_have_attribute("username")
    validate_does_not_have_attribute("password")
  end

  def validate_not_azure_oidc_credentials
    validate_does_not_have_attribute("tenant-id")
    validate_does_not_have_attribute("client-id")
  end

  def validate_jfrog_oidc_credentials
    validate_has_attribute("jfrog-oidc-provider-name")
    validate_has_attribute("url")

    validate_does_not_have_attribute("token")
    validate_does_not_have_attribute("username")
    validate_does_not_have_attribute("password")
  end

  def validate_not_jfrog_oidc_credentials
    validate_does_not_have_attribute("jfrog-oidc-provider-name")
  end

  def validate_aws_oidc_credentials
    validate_has_attribute("aws-region")
    validate_has_attribute("account-id")
    validate_has_attribute("role-name")
    validate_has_attribute("domain")
    validate_has_attribute("domain-owner")

    validate_does_not_have_attribute("token")
    validate_does_not_have_attribute("username")
    validate_does_not_have_attribute("password")
  end

  def validate_not_aws_oidc_credentials
    validate_does_not_have_attribute("aws-region")
    validate_does_not_have_attribute("account-id")
    validate_does_not_have_attribute("role-name")
    validate_does_not_have_attribute("domain")
    validate_does_not_have_attribute("domain-owner")
  end

  def validate_cloudsmith_oidc_credentials
    validate_has_attribute("namespace")
    validate_has_attribute("service-slug")
    validate_has_attribute("audience")

    validate_does_not_have_attribute("token")
    validate_does_not_have_attribute("username")
    validate_does_not_have_attribute("password")
  end

  def validate_not_cloudsmith_oidc_credentials
    validate_does_not_have_attribute("namespace")
    validate_does_not_have_attribute("service-slug")
    validate_does_not_have_attribute("api-host")
  end

  def validate_gcp_oidc_credentials
    validate_has_attribute("workload-identity-provider")

    validate_does_not_have_attribute("token")
    validate_does_not_have_attribute("username")
    validate_does_not_have_attribute("password")
  end

  def validate_not_gcp_oidc_credentials
    validate_does_not_have_attribute("workload-identity-provider")
    validate_does_not_have_attribute("service-account")
  end

  def validate_github_secret_format_or_guid(key)
    value = parsed_credentials[key].strip
    errors.add(:base, "#{key} must be present.") and return unless value

    return if value.include?("${{") && value.include?("}}")

    return if value.match?(/^[0-9a-f-]{36}$/i)

    errors.add(:base, "#{key} should be stored as a GitHub secret or be a valid literal value.")
  end
end
# rubocop:enable Metrics/ClassLength
