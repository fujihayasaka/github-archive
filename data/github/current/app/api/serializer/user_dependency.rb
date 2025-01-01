# typed: true
# frozen_string_literal: true

module Api::Serializer::UserDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer }

  include Api::Serializer::AvatarsDependency

  EMPLOYEE_IDS_REFRESH = 1.hour

  EMPLOYEE_IDS_KEY = "github_employee_ids"

  def simple_user_hash(user, options = {})
    return nil if !user

    options = Api::SerializerOptions.from(options)
    current_user = options[:current_user]
    base_path = Api::LegacyEncode.encode("/users/#{user.login_for_api(use: options[:serialize_login])}", /\[|\]/)
    hash = {
      login: user.login_for_api(use: options[:serialize_login]),
      id: user.id,
      node_id: global_id_for(user, options),
      avatar_url: avatar(user),
      gravatar_id: "",
      url: url(base_path, options),
      html_url: user.permalink,
      followers_url: url("#{base_path}/followers", options),
      following_url: url("#{base_path}/following{/other_user}", options),
      gists_url: url("#{base_path}/gists{/gist_id}", options),
      starred_url: url("#{base_path}/starred{/owner}{/repo}", options),
      subscriptions_url: url("#{base_path}/subscriptions", options),
      organizations_url: url("#{base_path}/orgs", options),
      repos_url: url("#{base_path}/repos", options),
      events_url: url("#{base_path}/events{/privacy}", options),
      received_events_url: url("#{base_path}/received_events", options),
      type: user.user_type,
      user_view_type: "public",
      site_admin: instance_admin?(user, viewer: current_user),
    }

    if options[:private]
      hash[:user_view_type] = "private"
    end

    hash[:ldap_dn] = user.ldap_dn if user.ldap_mapped?

    hash
  end

  def search_user_hash(user, options = {})
    return nil if !user

    hash = simple_user_hash(user, options)
    options = Api::SerializerOptions.from(options)

    if options.accepts_semantic_version?("extended-search-results")
      profile = user.profile
      viewer = options[:current_user]

      hash.update \
        name: fetch_field(profile, :name),
        location: fetch_field(profile, :location),
        email: user.publicly_visible_email(logged_in: !options[:exclude_email]),
        hireable: fetch_field(profile, :hireable),
        bio: fetch_field(profile, :bio),
        public_repos: user.repository_counts.public_repositories,
        public_gists: user.repository_counts.public_gists,
        followers: user.followers_count(viewer: viewer),
        following: user.following_count(viewer: viewer),
        created_at: time(user.created_at),
        updated_at: time(user.updated_at)
    end
    hash
  end

  # Creates a Hash to be serialized to JSON.
  #
  # user    - User instance.
  # options - Hash
  #           :repo - Repository instance that the user is a collaborator on.
  #
  # Returns a Hash if the User and Repository exist, or nil.
  def collaborator_hash(user, options = {})
    options = Api::SerializerOptions.from(options)
    repo    = options[:repo]

    return nil unless user.present?
    return nil unless repo.present?

    hash = simple_user_hash(user, options)
    hash.update(requested_identity_attrs(user, options: options))

    if user_perms = options[:user_permissions]&.[](user.id)
      hash.update(permissions: user_perms)
    else
      hash.update(permissions:  T.unsafe(self).permissions_hash(repo, actor: user))
    end

    if role_name = options[:user_roles]&.[](user.id)
      hash.update(role_name: role_name)
    else
      hash.update(role_name: T.unsafe(self).role_name(repo, user: user).to_s)
    end

    hash
  end

  # Creates a Hash to be serialized to JSON.
  #
  # user    - User instance.
  # options - Hash
  #           :full          - Boolean specifying we want the extended output.
  #           :private       - Boolean specifying we want the private output.
  #           :business_plus - Boolean specifying we want the business plan output.
  #           :exclude_email - Boolean specifying suppressing the user's profile email.
  #
  # Returns a Hash if the User exists, or nil.
  def user_hash(user, options = {})
    return nil if !user

    hash = simple_user_hash(user, options)
    options = Api::SerializerOptions.from(options)

    include_details = options[:full] || options[:private]

    if include_details
      profile = options[:profile] || user.profile
      hash.update \
        name: fetch_field(profile, :name),
        company: fetch_field(profile, :company),
        blog: fetch_field(profile, :blog).to_s,
        location: fetch_field(profile, :location),
        email: user_hash_email(user, options),
        hireable: fetch_field(profile, :hireable),
        bio: fetch_field(profile, :bio), # DEPRECATED: Will be removed in API v4.
        twitter_username: fetch_field(profile, :twitter_username)

      if options[:check_email_claimed]
        hash[:notification_email] = user.publicly_visible_email(logged_in: !options[:exclude_email])
      end
    end

    hash.update(requested_identity_attrs(user, options: options))

    if include_details
      current_user = options[:current_user]
      hash.update \
        public_repos: user.repository_counts.public_repositories,
        public_gists: user.repository_counts.public_gists,
        followers: user.followers_count(viewer: current_user),
        following: user.following_count(viewer: current_user),
        created_at: time(user.created_at),
        updated_at: time(user.updated_at)

      hash[:suspended_at] = user.suspended_at if GitHub.enterprise?
    end

    hash.update(user_view_type: "public")

    if options[:private]
      hash.update \
        private_gists: user.repository_counts.private_gists,
        total_private_repos: user.repository_counts.private_repositories,
        owned_private_repos: user.repository_counts.owned_private_repositories,
        disk_usage: user.disk_usage,
        collaborators: user.collaborators_count,
        two_factor_authentication: user.two_factor_authentication_enabled?,
        user_view_type: "private"

      if !GitHub.enterprise?
        hash.update(business_plus: user.business_plus?) if options[:business_plus]

      end
    end

    if (options[:private] || options[:plan]) && !GitHub.enterprise?
      hash.update \
        plan: {
          name: user.plan.display_name,
          space: user.plan.space / 1.kilobyte,
          collaborators: 0,
          private_repos: user.plan.repos,
        }
    end

    hash
  end

  # Returns EMU user's primary email with '+' if it's not claimed
  def user_hash_email(user, options)
    if options[:check_email_claimed] && !options[:exclude_email] && use_primary_email?(user)
      return user.email
    end

    user.publicly_visible_email(logged_in: !options[:exclude_email])
  end

  HovercardFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on Hovercard {
      contexts {
        message
        octicon
      }
    }
  GRAPHQL

  def graphql_hovercard_hash(hovercard, options = {})
    hovercard = HovercardFragment.new(hovercard)

    {
      contexts: hovercard.contexts.map do |context|
        {
          message: context.message,
          octicon: context.octicon,
        }
      end,
    }
  end

  SimpleUserFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on Node {
      id
      ...on RepositoryOwner {
        login
        databaseId
        url
        avatarUrl
      }
      ...on User {
        isSiteAdmin
        isEmployee
        ldapDN
      }
      ...on Bot {
        login
        databaseId
        url
        avatarUrl
      }
      ...on Mannequin {
        login
        databaseId
        url
        avatarUrl
      }
    }
  GRAPHQL

  def graphql_simple_user_hash(user, options = {})
    options = Api::SerializerOptions.from(options)
    user = SimpleUserFragment.new(user)

    return unless user

    make_simple_graphql_user_hash(user, options)
  end

  # Internal: Determine whether the API response can safely honor the
  # `user-identity` media type parameter.
  #
  # If the user profile is not already loaded (i.e., "prefilled"), then the API
  # method probably doesn't officially support the `user-identity` parameter.
  # Prefilling is essential for any API methods that can return a list of users.
  # Failure to prefill the profile would lead to an n+1 query loading the
  # profile for each user in the list.
  #
  # user - A User instance.
  #
  # Returns a Boolean.
  def supports_user_identity_param?(user)
    user.association(:profile).loaded?
  end

  # Builds an uber-minimal User hash to use when autocompleting users.
  #
  # user    - User instance.
  # options - Hash of valid Api::Serializer options
  #
  # Returns a Hash if the User exists, or nil.
  def mentionable_user_hash(user, options = {})
    return nil if !user

    profile = user.profile
    {
      login: user.login_for_api(use: options[:serialize_login]),
      name: profile && profile.name,
      email: user.public_attribution_email,
      avatar_url: avatar(user),
    }
  end

  # Builds a contributor hash based on raw data returned from
  # Repository#contributors
  #
  # contributor - The [User|Hash, Integer] pair. Integer is contributions count.
  # options - Hash of valid Api::Serializer options
  #
  # Returns a Hash if the user is present, or nil.
  def contributor_hash(contributor, options = {})
    user, count = contributor
    hash = case user
    when User
      user_hash(user, content_options(options))
    when Hash
      user.merge(type: "Anonymous")
    else
      raise ArgumentError, "expected user to be User or Hash"
    end

    hash.update(contributions: count)
  end

  # Creates a Hash to be serialized to JSON.
  #
  # email   - UserEmail instance
  # options - Hash
  #
  # Returns a Hash if the email exists, or nil.
  def user_email_hash(email, options = {})
    return nil if !email

    options = Api::SerializerOptions.from(options)

    user_email = if options[:check_email_claimed]
      if email.claimed? && options.current_user
        options.current_user.remove_shortcode(email.email)
      else
        email.email
      end
    else
      if options.current_user.present? # rubocop:disable GitHub/CurrentUserNilCheck
        options.current_user.remove_shortcode(email.email)
      else
        email.email
      end
    end

    verified = if options[:check_email_claimed]
      GitHub.email_verification_enabled? ? email.claimed? : true
    else
      GitHub.email_verification_enabled? ? email.verified? : true
    end

    if options.wants_beta_media_type? && !options.changeset_active?(:deprecate_beta_media_type)
      # < deprecated
      user_email
    else
      {}.tap do |email_hash|
        email_hash[:email]    = user_email
        email_hash[:primary]  = email.primary?
        email_hash[:verified] = verified
        email_hash[:visibility] = email.primary? ? email.visibility : nil

        if options.full
          email_hash[:user] = user_hash(email.user, private: true, business_plus: true)
        end
      end
    end
  end

  # Creates a Hash to be serialized to JSON.
  #
  # public_key - PublicKey instance
  # options    - Hash
  #
  # Returns a Hash if the public_key exists, or nil.
  def public_key_hash(public_key, options = {})
    return nil if !public_key
    options = Api::SerializerOptions.from(options)

    always_include_last_used = FeatureFlag.vexi.enabled?(:list_user_ssh_keys_include_last_used, default: false)

    hash = {
      id: public_key.id,
      key: public_key.key,
      created_at: time(public_key.created_at),
    }

    if always_include_last_used
      hash.update last_used: time(public_key.accessed_at)
    end

    if options.simple
      hash
    else
      url_suffix = if public_key.repository.present?
        "/repos/#{public_key.repository.name_with_owner_for_api(use: options[:serialize_login])}/keys/#{public_key.id}"
      else
        "/user/keys/#{public_key.id}"
      end

      hash.update \
        url: url(url_suffix, options),
        title: public_key.title,
        verified: public_key.verified?,
        read_only: public_key.read_only?
    end

    # if the public key is a deploy key, add last accessed and added by info
    if public_key.repository_key?
      if always_include_last_used
        hash.update \
          added_by: nil
      else
        hash.update \
          last_used: time(public_key.accessed_at),
          added_by: nil
      end

      if authorization = public_key.try(:oauth_authorization)
        hash.update added_by: authorization.user.login_for_api(use: options[:serialize_login])
      elsif public_key.creator.present?
        hash.update added_by: public_key.creator.login_for_api(use: options[:serialize_login])
      end

      disabled_by_policy, _ = public_key.repository.deploy_keys_disabled_by_policy_with_policy_source
      hash.update enabled: !disabled_by_policy
    end

    if options.detail
      if always_include_last_used
        hash.update \
          user_id: public_key.user_id,
          repository_id: public_key.repository_id
      else
        hash.update \
          last_used: public_key.accessed_at,
          user_id: public_key.user_id,
          repository_id: public_key.repository_id
      end
    end

    hash
  end

  # Creates a Hash to be serialized to JSON.
  #
  # signing_key - GitSigningSshPublicKey instance
  # options - Hash
  #
  # Returns a Hash if the signing_key exists, or nil.
  def signing_key_hash(signing_key, options = {})
    return nil if !signing_key
    hash = {
      id: signing_key.id,
      key: signing_key.key,
      title: signing_key.title,
      created_at: signing_key.created_at,
    }

    hash
  end

  # Creates a Hash to be serialized to JSON.
  #
  # gpg_key - GpgKey instance
  # options - Hash
  #
  # Returns a Hash if the gpg_key exists, or nil.
  def gpg_key_hash(gpg_key, options = {})
    return nil if !gpg_key

    subkeys = gpg_key.subkeys.map { |sk| gpg_key_hash(sk, options) }

    business = gpg_key.user.enterprise_managed_business
    emails = gpg_key.emails.map do |email|
      { email: email.email, verified: gpg_key.allowed_email?(email.email, business: business) }
    end

    hash = {
      id: gpg_key.id,
      primary_key_id: gpg_key.primary_key_id,
      key_id: gpg_key.hex_key_id,
      raw_key: gpg_key.raw_key,
      public_key: Base64.strict_encode64(gpg_key.public_key),
      emails: emails,
      subkeys: subkeys,
      can_sign: gpg_key.can_sign,
      can_encrypt_comms: gpg_key.can_encrypt_comms,
      can_encrypt_storage: gpg_key.can_encrypt_storage,
      can_certify: gpg_key.can_certify,
      created_at: gpg_key.created_at,
      expires_at: gpg_key.expires_at,
      revoked: gpg_key.revoked?,
    }

    hash[:name] = gpg_key.name if gpg_key.name.present?

    hash
  end

  # Creates a Hash to be serialized to JSON.
  #
  # access - OauthAccess.
  #
  # Returns a Hash if the OauthAccess exists, or nil.
  def oauth_access_hash(access, options = nil)
    return nil if !access
    options = Api::SerializerOptions.from(options)
    hash = {
      id: access.id,
      url: url("/authorizations/#{access.id}"),
      app: oauth_application_hash(access.safe_app),
      token: options[:token].to_s,
      hashed_token: access.hashed_token(hex: true),
      token_last_eight: access.token_last_eight,
      note: access.description,
      note_url: access.note_url,
      created_at: time(access.created_at),
      updated_at: time(access.updated_at),
      scopes: access.scopes,
      fingerprint: access.fingerprint,
      expires_at: access.expires_at
    }

    hash[:user] = simple_user_hash(access.user, content_options(options)) if options && options[:user]

    if (installation = options[:installation])
      hash[:installation] = T.unsafe(self).scoped_installation_hash(installation, content_options(options))
    end

    hash
  end

  # Creates a Hash to be serialized to JSON.
  #
  # access - OauthAccess.
  #
  # Returns a Hash if the OauthAccess exists, or nil.
  def personal_access_token_hash(access, options = nil)
    return nil if !access

    options = Api::SerializerOptions.from(options)

    {
      id: access.id,
      url: url("/authorizations/#{access.id}"),
      token: options[:token].to_s,
      hashed_token: access.hashed_token(hex: true),
      token_last_eight: access.token_last_eight,
      note: access.description,
      note_url: access.note_url,
      created_at: time(access.created_at),
      updated_at: time(access.updated_at),
      scopes: access.scopes,
      fingerprint: access.fingerprint,
      expires_at: access.expires_at,
      user: simple_user_hash(access.user, options)
    }
  end

  # Creates a Hash to be serialized to JSON.
  #
  # authorization - OauthAuthorization.
  #
  # Returns a Hash if the OauthAuthorization exists, or nil.
  def oauth_authorization_hash(authorization, options = nil)
    return nil if !authorization
    hash = {
      id: authorization.id,
      url: url("/applications/grants/#{authorization.id}"),
      app: oauth_application_hash(authorization.safe_app),
      created_at: time(authorization.created_at),
      updated_at: time(authorization.updated_at),
      scopes: authorization.scopes,
    }

    hash
  end

  # Creates a Hash to be serialized to JSON.
  #
  # access - OauthApplication.
  #
  # Returns a Hash if the OauthApplication exists, or nil.
  def oauth_application_hash(app, options = nil)
    return nil if !app
    {
      name: app.name,
      url: app.url,
      client_id: app.key,
    }
  end

  # Creates a Hash to be serialized to JSON.
  #
  # social_account - SocialAccount.
  #
  # Returns a Hash if the SocialAccount exists, or nil.
  def social_account_hash(social_account, options = nil)
    return nil if !social_account

    { provider: social_account.key, url: social_account.url }
  end

  # Determine if a given user is an instance admin, for serializing the
  # site_admin field on user resources.
  #
  # An instance admin is defined as:
  #
  # GitHub.com: staff users
  # GitHub Enterprise: site admins
  #
  # Returns a Boolean.
  def instance_admin?(user, viewer:)
    return false unless user.user?
    return false if user.private_profile_for?(viewer)

    user.site_admin_without_two_factor_check? || github_employee?(user)
  end

  private

  # Fetch the value of a field
  #
  # obj - e.g. a Profile
  # name - name of the field to lookup
  #
  # Returns the value of the field, or nil, if the value is nil or empty
  def fetch_field(obj, name)
    obj && obj.send(name).presence
  end

  # Get the identity attributes for the user if they were requested
  #
  # user    - The user whose identity information should be added to the hash.
  # options - API options that we'll use to check whether or not the identity
  #           info was requested.
  #
  # Returns a hash containing the user's identity attributes, or an empty hash
  # if identity was not requested.
  def requested_identity_attrs(user, options:)
    if options.accepts_param?(:'user-identity') && supports_user_identity_param?(user)
      { name: user.profile_name, email: user.profile_email }
    else
      {}
    end
  end

  # Check if a user is in the cached list of GitHub employees.
  #
  # user - a User object.
  #
  # Returns a Boolean.
  def github_employee?(user)
    return false unless GitHub.require_employee_for_site_admin?

    github_employee_user_ids_set.include?(user.id)
  end

  # Internal: Cache GitHub employees team user IDs for faster serialization of
  # site_admin field on user resources.
  #
  # Returns a Set of integers.
  def github_employee_user_ids_set
    return @github_employee_user_ids_set if defined?(@github_employee_user_ids_set)

    return Set.new unless GitHub.require_employee_for_site_admin?

    github_employee_user_ids = GitHub.cache.fetch(EMPLOYEE_IDS_KEY, ttl: EMPLOYEE_IDS_REFRESH) do
      if team = FeatureFlag.employees_team
        team.member_ids
      else
        []
      end
    end

    @github_employee_user_ids_set = github_employee_user_ids.to_set
  end

  # Convert a User fragment into a hash
  # user graphQL fragment object (SimpleUserFragment)
  # include_nonhumans Boolean - should we include nonhuman fields (Bots and Mannequins)
  # Returns a hash
  def make_simple_graphql_user_hash(user, options = {}, include_nonhumans = true)
    # Hash is used specifically for GraphQL and login in GraphQL already return display login
    login = user.login # rubocop:disable GitHub/DoNotAllowLogin

    if include_nonhumans && user.is_a?(Api::App::PlatformTypes::Bot)
      # See https://github.com/github/github/issues/93032#issuecomment-407761734
      login = "#{login}#{Bot::LOGIN_SUFFIX}"
    end

    base_path = Api::LegacyEncode.encode("/users/#{login}", /\[|\]/)
    html_url  = user.url.to_s

    if include_nonhumans && user.is_a?(Api::App::PlatformTypes::Mannequin)
      ghost_user_hash = simple_user_hash(User.ghost, content_options(options))
      # See https://github.com/github/github/issues/93032#issuecomment-407761734
      base_path = Api::LegacyEncode.encode("/users/#{ghost_user_hash[:login]}", /\[|\]/)
      html_url = ghost_user_hash[:url].to_s
    end

    avatar_url = user.avatar_url.to_s
    avatar_url += "?" unless avatar_url["?"]

    hash = {
      login:               login,
      id:                  user.database_id,
      node_id:             user.id,
      avatar_url:          avatar_url,
      gravatar_id:         "",
      url:                 url(base_path, options),
      html_url:            html_url,
      followers_url:       url("#{base_path}/followers", options),
      following_url:       url("#{base_path}/following{/other_user}", options),
      gists_url:           url("#{base_path}/gists{/gist_id}", options),
      starred_url:         url("#{base_path}/starred{/owner}{/repo}", options),
      subscriptions_url:   url("#{base_path}/subscriptions", options),
      organizations_url:   url("#{base_path}/orgs", options),
      repos_url:           url("#{base_path}/repos", options),
      events_url:          url("#{base_path}/events{/privacy}", options),
      received_events_url: url("#{base_path}/received_events", options),
      type:                user.__typename,
      user_view_type:           "public"
    }

    if options[:private]
      hash[:user_view_type] = "private"
    end

    if user.is_a?(Api::App::PlatformTypes::User)
      if user.is_site_admin || user.is_employee
        hash[:site_admin] = true
      else
        hash[:site_admin] = false
      end
    else
      hash[:site_admin] = false
    end

    # FIXME: It'd be nice not to fetch user.ldap_dn at all if GitHub.auth.ldap?
    # is false. Right now we're doing the work to fetch that field and then
    # throwing it away.
    if user.is_a?(Api::App::PlatformTypes::User) && GitHub.auth.ldap? && user.ldap_dn?
      hash[:ldap_dn] = user.ldap_dn
    end

    hash
  end

  # Private: Should we return the the primary email for the user?
  # Only returns true for enterprise managed users in dotcom with primary email that is not claimed.
  #
  # Returns boolean
  def use_primary_email?(user)
    return false unless user&.user?
    return false unless user.is_enterprise_managed?
    return false if GitHub.multi_tenant_enterprise?

    !user.primary_user_email&.claimed?
  end
end
