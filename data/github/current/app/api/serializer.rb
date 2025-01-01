# typed: true
# frozen_string_literal: true

module Api::Serializer
  extend self
  extend UrlHelper
  include UrlHelper

  extend Api::Serializer::AvatarsDependency
  extend Api::Serializer::GraphqlHelperDependency

  # These depend only on the graphql dependencies, and nobody
  # depends on them in turn.
  extend Api::Serializer::MarketplaceListingDependency
  extend Api::Serializer::TopicsDependency
  extend Api::Serializer::VerifiableDependency

  # These depend only on the graphql dependencies,
  # and other dependencies depend on them in turn.
  # Order is important.
  extend Api::Serializer::CodesOfConductDependency
  extend Api::Serializer::CommitsDependency
  extend Api::Serializer::LicensesDependency
  extend Api::Serializer::UserDependency
  extend Api::Serializer::ProjectsDependency
  extend Api::Serializer::ProjectsV2Dependency
  extend Api::Serializer::ReactionsDependency
  extend Api::Serializer::OrganizationsDependency
  extend Api::Serializer::IntegrationsDependency
  extend Api::Serializer::PullRequestReviewsDependency
  extend Api::Serializer::RepositoriesDependency
  extend Api::Serializer::TeamDiscussionsDependency
  extend Api::Serializer::TeamRepositoryDependency
  extend Api::Serializer::IssuesDependency
  extend Api::Serializer::PullsDependency
  extend Api::Serializer::DeploymentsDependency
  extend Api::Serializer::ChecksDependency
  extend Api::Serializer::WorkflowsDependency
  extend Api::Serializer::JobsDependency
  extend Api::Serializer::EnvironmentsDependency
  extend Api::Serializer::DeploymentRequestsDependency

  # These don't rely on any other dependencies, and nothing
  # relies on them in return.
  # They can therefore be included at the end, in any order.
  extend Api::Serializer::ActionsRunnerApplicationsDependency
  extend Api::Serializer::ActionsRunnersDependency
  extend Api::Serializer::ActionsLargerRunnersDependency
  extend Api::Serializer::ActionsPermissionsDependency
  extend Api::Serializer::ActionsSecretsDependency
  extend Api::Serializer::ActionsVariablesDependency
  extend Api::Serializer::CodeScanningDependency
  extend Api::Serializer::ArtifactsDependency
  extend Api::Serializer::BillingDependency
  extend Api::Serializer::CodeqlDatabaseDependency
  extend Api::Serializer::CodeownersDependency
  extend Api::Serializer::CouponDependency
  extend Api::Serializer::CredentialAuthorizationsDependency
  extend Api::Serializer::DependabotAlertsDependency
  extend Api::Serializer::CodeSecurityConfigurationsDependency
  extend Api::Serializer::DependabotSecretsDependency
  extend Api::Serializer::DeploymentStatusesDependency
  extend Api::Serializer::DiscussionsDependency
  extend Api::Serializer::EnterpriseAppsDependency
  extend Api::Serializer::EnterprisesDependency
  extend Api::Serializer::EnterpriseTeamsDependency
  extend Api::Serializer::EventsDependency
  extend Api::Serializer::GistsDependency
  extend Api::Serializer::GitDataDependency
  extend Api::Serializer::HooksDependency
  extend Api::Serializer::ImporterDependency
  extend Api::Serializer::IntegrationInstallationsDependency
  extend Api::Serializer::InteractionLimitsDependency
  extend Api::Serializer::InternalDependency
  extend Api::Serializer::LegacyDependency
  extend Api::Serializer::MergeQueueDependency
  extend Api::Serializer::MigrationsDependency
  extend Api::Serializer::NetworkConfigurationsDependency
  extend Api::Serializer::NotificationsDependency
  extend Api::Serializer::OrganizationTeamSyncDependency
  extend Api::Serializer::PackagesDependency
  extend Api::Serializer::OrganizationProgrammaticAccessGrantRequestDependency
  extend Api::Serializer::PorterDependency
  extend Api::Serializer::PreReceiveDependency
  extend Api::Serializer::RateLimitDependency
  extend Api::Serializer::ReachabilityDependency
  extend Api::Serializer::RegistryPackagesDependency
  extend Api::Serializer::RegistryPackagesV2Dependency
  extend Api::Serializer::ReminderDependency
  extend Api::Serializer::RepositoryAdvisoriesDependency
  extend Api::Serializer::RepositoryCodeqlVariantAnalysisDependency
  extend Api::Serializer::RepositoryVulnerabilityAlertsDependency
  extend Api::Serializer::ScimDependency
  extend Api::Serializer::SearchDependency
  extend Api::Serializer::SecretScanningAlertDependency
  extend Api::Serializer::SecurityAdvisoriesDependency
  extend Api::Serializer::SponsorsTierDependency
  extend Api::Serializer::StafftoolsRoleDependency
  extend Api::Serializer::StarsDependency
  extend Api::Serializer::StatsDependency
  extend Api::Serializer::StatusesDependency
  extend Api::Serializer::TrafficDependency
  extend Api::Serializer::UploadableDependency
  extend Api::Serializer::VulnerabilitiesDependency
  extend Api::Serializer::CodespacesDependency
  extend Api::Serializer::CodespacesSecretsDependency
  extend Api::Serializer::RepositoryDependencyGraphSnapshot
  extend Api::Serializer::ClassroomRepositoriesDependency
  extend Api::Serializer::CustomRolesDependency
  extend Api::Serializer::FineGrainedPermissionsDependency
  extend Api::Serializer::OrganizationFineGrainedPermissionsDependency
  extend Api::Serializer::PagesDependency
  extend Api::Serializer::ActionsCacheDependency
  extend Api::Serializer::OrganizationActionsCacheDependency
  extend Api::Serializer::EnterpriseActionsCacheDependency
  extend Api::Serializer::MergeGroupDependency
  extend Api::Serializer::OrganizationOIDCCustomSubTemplateSerializer
  extend Api::Serializer::PullRequest::CommentsDependency
  extend Api::Serializer::GlobalFlagsDependency
  extend Api::Serializer::OrganizationProgrammaticAccessGrantDependency
  extend Api::Serializer::OrganizationProgrammaticAccessGrantRequestDependency
  extend Api::Serializer::CopilotForBusinessDependency
  extend Api::Serializer::KnowledgeBaseDependency
  extend RepositoryRulesets::HashBuilder
  extend Api::Serializer::ExemptionsDependency
  extend Api::Serializer::DesktopDependency
  extend Api::Serializer::DsrDependency

  # Public: The absolute URL to a preferred file (CONTRIBUTING, README, etc.)
  #
  # type - A Symbol type from PreferredFile::Types.
  # repository - A Repository to find the file in.
  #
  # See preferred_file_path in UrlHelper
  #
  # Returns a String or nil.
  def preferred_file_url(type:, repository:)
    path = preferred_file_path(type: type, repository: repository)
    return unless path
    "#{base_url}#{path}"
  end

  COLLECTION_CLASSES = [
    Array,
    WillPaginate::Collection,
    ActiveRecord::Relation,
    ActiveRecord::Associations::CollectionProxy,
    GH::Domain::Collection
  ]

  # @param map_items [Boolean] if true and object is an instance of {COLLECTION_CLASSES}, serialize each object separately
  def serialize(method, obj, options = {})
    # This option is sometimes provided to ad-hoc serialize calls, but it's
    # not part of Api::Serializer options.
    map_items = if options.is_a?(Hash)
      options.delete(:map_items)
    else
      true
    end

    if options[:global_id_selection].nil?
      # This code is for backwards compat, where `_hash` methods were called directly.
      # Ideally, this option would contain a global_id_selection, and we'd track associations.
      # But, it didn't _used_ to work this way :S
      options[:global_id_selection] = { user_preference: false, user_opt_out: false }
      enable_strict_loading = false
    else
      enable_strict_loading = !options[:skip_strict_loading]
    end

    if map_items && COLLECTION_CLASSES.any? { |collection_class| obj.is_a?(collection_class) }
      serialize_collection(method, obj, options, enable_strict_loading: enable_strict_loading)
    else # ActiveRecord::Base, Hash
      # When serializing a single record, set strict loading mode to allow
      # lazy loading while catching N+1's
      if Rails.env.test? && enable_strict_loading && obj.is_a?(ActiveRecord::Base)
        obj.strict_loading!(mode: :n_plus_one_only)
      end
      serialize_record(method, obj, options)
    end
  end

  def validation_errors(validation_errors, resource = nil)
    errors = []

    resource = resource.to_s if resource.is_a?(Symbol)

    if resource && !resource.is_a?(String)
      Failbot.report(ArgumentError.new("Resource of type `#{resource.class.name}` is not a string."))
      resource = resource.class.name
    end

    resource ||= validation_errors.instance_variable_get(:@base).class.name

    opt = { resource: resource }
    validation_errors.each do |error|
      # Sinatra does not use the new error object API like rails does,
      # So if this error came from Sinatra it will still be an Array
      # instead of an AM:Error object.
      if error.is_a?(Array)
        key = error[0]
        message = error[1]
      else
        key = error.attribute
        message = error.message
      end

      if code = Api::App::ErrorDependency::ERROR_MAP[message]
        errors << opt.merge(code: code, field: key)
      else
        if key.to_s == "base"
          errors << opt.merge(code: :custom, message: message)
        else
          errors << opt.merge(code: :custom, field: key, message: "#{key} #{message}")
        end
      end
    end
    errors
  end

  ValidationErrorFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on ValidationError {
      shortMessage
      attribute
      path
    }
  GRAPHQL

  def url(suffix, options = nil)
    "#{GitHub.api_url}#{suffix}"
  end

  def html_url(suffix, options = nil)
    url_with_query GitHub.url + suffix.to_s, options
  end

  def encoded_html_url(prefix, path)
    encode(prefix) + u(path)
  end

  def encoded_content_url(prefix, path, query = {})
    url_with_query(encode(url(prefix)) + u(path), query)
  end

  def model_id_for_global_id(global_id)
    _, model_id = Platform::Helpers::NodeIdentification.from_global_id(global_id)

    model_id.to_i
  end

  def time(t)
    t ? t.to_time.utc.xmlschema : nil
  end

  private

  def serialize_collection(method, obj, options, enable_strict_loading:)
    GitHub.tracer.in_span("Api::Serializer#serialize_collection", kind: :internal) do |_|
      obj.map do |resource|
        # Turn on strict loading to avoid N+1's from Active Record associations
        # on serialization
        if Rails.env.test? && enable_strict_loading && obj.respond_to?(:strict_loading!)
          resource.strict_loading!
        end

        serialize_record(method, resource, options)
      end
    end
  end

  def serialize_record(method, resource, options)
    GitHub.tracer.in_span("Api::Serializer#serialize_record", kind: :internal, attributes: { "gh.api.serialization.name" => method.to_s }) do |_|
      send(method, resource, options)
    end
  end

  def url_with_query(path, options)
    return path if options.nil? || options.empty?
    parts = []
    options.each do |key, value|
      parts << "#{u(key)}=#{u(value)}"
    end

    "#{path}?#{query_parts(options)}"
  end

  def query_parts(options)
    return nil unless options.present?

    parts = []
    options.each do |key, value|
      parts << "#{u(key)}=#{u(value)}"
    end

    "#{parts * "&"}"
  end

  def content_options(options)
    { serialize_login: options[:serialize_login], accept_mime_types: options[:accept_mime_types], global_id_selection: options[:global_id_selection] }
  end

  # Escapes any characters not allowed in a URL into their hex equivalents,
  # including non-ascii unicode characters that may appear in user created
  # directory or file names.
  #
  # Examples
  #
  #   url = 'https://api.github.com/repos/github/hubot/contents/más?q=olé'
  #   url = encode(url)
  #   # => 'https://api.github.com/repos/github/hubot/contents/m%C3%A1s?q=ol%C3%A9'
  #
  # url - The String URL to escape.
  #
  # Returns an escaped URL String.
  def encode(url)
    Addressable::URI.encode(url)
  end

  def u(s)
    Api::LegacyEncode.encode(s.to_s, /[^-_.!~*'()a-zA-Z\d;\/:@&=$,\[\]]/n)
  end

  def repo_path(options, record)
    if path = options[:repo_path]
      return path
    end

    repo = options[:repo] || record.repository

    if repo.respond_to?(:name_with_owner_for_api)
      repo.name_with_owner_for_api(use: options[:serialize_login])
    elsif repo.respond_to?(:name_with_owner)
      # preserving this case as a fallback to maintain legacy typing behavior
      repo.name_with_owner # rubocop:disable GitHub/DoNotAllowNameWithOwner
    else
      repo.to_s
    end
  end

  def time_from_string(iso8601_timestamp_string)
    return if iso8601_timestamp_string.nil?

    Time.iso8601 iso8601_timestamp_string
  end

  # Encode a Ruby object using Base64.encode and optionally
  # time the operation.
  #
  # data - Object data to be encoded
  # options - Hash
  #         - :stats_key String key for GitHub.dogstats.
  def encode_base64(data, options = {})
    if key = options[:stats_key]
      GitHub.dogstats.time("base64", tags: ["via:api", "key:#{key}"]) do
        Base64.encode64(data)
      end
    else
      Base64.encode64(data)
    end
  end

  # Handle various body formats for Accept mime types
  #
  # record - an object that responds to #body, #body_html, and #body_text
  # options - Hash
  def mime_body_hash(record, options)
    params   = options[:mime_params] || []
    full     = params.include? :full
    any_body = false
    hash     = {}
    if full || params.include?(:html)
      any_body = true
      hash.update body_html: record.body_html
    end
    if full || params.include?(:text)
      any_body = true
      hash.update body_text: record.body_text
    end
    if full || !any_body || params.include?(:raw)
      hash.update body: record.body
    end

    hash
  end

  class GlobalIdOptionMissingError < StandardError
  end

  def global_id_for(object, options)
    case options[:global_id_selection]
    when Hash
      Platform::Helpers::GlobalId.for(object, **options[:global_id_selection])
    when nil
      if Rails.env.production?
        err = GlobalIdOptionMissingError.new
        err.set_backtrace(caller)
        Failbot.report!(err)
      else
        raise GlobalIdOptionMissingError
      end
      object.global_relay_id
    else
      raise ArgumentError, "Unexpected options[:global_id_selection]: #{options[:global_id_selection].inspect} (expected a Hash or nil)"
    end
  end
end
