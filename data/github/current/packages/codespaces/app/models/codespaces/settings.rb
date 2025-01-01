# typed: true
# frozen_string_literal: true

##
# Codespaces::Settings is a class that provides access to the settings
# that are consistent for a user across all codespaces.
# They are stored in the User Configurable Settings table
# This class offers Model like behavior for defaults, updating
# validation and saving.

# At the moment, we only ever need one attribute at a time, so I made the attributes lazy load
# In the future we may want to batch load them all at once.
#
class Codespaces::Settings
  class UserMissing < StandardError
  end
  include ActiveModel::AttributeMethods
  include ActiveModel::Validations

  attr_reader :user

  PREFERRED_EDITOR_VSCODE = "vscode"
  PREFERRED_EDITOR_VSCODE_WEB = "web"
  PREFERRED_EDITOR_JETBRAINS = "jetbrains"
  PREFERRED_EDITOR_JUPYTER = "jupyter"
  DEFAULT_TELEMETRY_LEVEL = "all"
  EDITORS = [PREFERRED_EDITOR_VSCODE, PREFERRED_EDITOR_VSCODE_WEB, PREFERRED_EDITOR_JETBRAINS, PREFERRED_EDITOR_JUPYTER].freeze
  WEB_EDITORS = [PREFERRED_EDITOR_VSCODE_WEB, PREFERRED_EDITOR_JUPYTER].freeze
  PREFERRED_HOST_IMAGE_STABLE = "Stable"
  PREFERRED_HOST_IMAGE_BETA = "Beta"
  HOST_IMAGES = [PREFERRED_HOST_IMAGE_STABLE, PREFERRED_HOST_IMAGE_BETA].freeze
  DEFAULT_VSCODE_CHANNEL = "stable"
  VSCODE_CHANNELS = %w[stable insider].freeze
  VALID_TELEMETRY_LEVELS = %w[all error crash off].freeze
  VALID_LOCATIONS = Codespaces::Locations::Region.public.map(&:id)
  DEFAULT_EXTENSIONS = %w[GitHub.vscode-pull-request-github github.github-vscode-theme].freeze

  validates :user, :vscode_channel, presence: true
  validates :preferred_editor, inclusion: { in: EDITORS, message: "is not a valid editor" }
  validates :preferred_host_image, inclusion: { in: HOST_IMAGES, message: "is not a valid host image" }
  validates :vscode_channel, inclusion: { in: VSCODE_CHANNELS, message: "must be a valid channel" }
  validates :default_location, inclusion: { in: VALID_LOCATIONS, message: "must be a valid location" }, allow_nil: true
  validates :default_idle_timeout, numericality: { only_integer: true, greater_than_or_equal_to: (Codespaces::Vscs::MIN_IDLE_TIME / 1.minute), less_than_or_equal_to: (Codespaces::Vscs::MAX_IDLE_TIME / 1.minute), message: "must be an integer between #{Codespaces::Vscs::MIN_IDLE_TIME / 1.minute} and #{Codespaces::Vscs::MAX_IDLE_TIME / 1.minute} minutes" }, allow_nil: true
  validates :default_retention_period, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: (Codespace::MAX_RETENTION_PERIOD), message: "must be an integer between 0-#{Codespace::MAX_RETENTION_PERIOD} minutes or nil" }, allow_nil: true
  validates :telemetry_level, inclusion: { in: VALID_TELEMETRY_LEVELS, message: "must be a valid telemetry level" }

  # Get a new instance of the Settings class for the given user.
  def self.for_user(user)
    new(user: user)
  end

  # Get a new instance of the Settings class for the current user and save.
  def self.create(user:)
    new(user: user).save
  end

  def initialize(user:)
    raise UserMissing unless user.is_a?(User)
    @user = user
    @updates = [] # Keep track of changes to the settings so we can save them.
  end

  def preferred_editor
    return unless user.present?
    @preferred_editor ||= user.codespace_preferred_editor
  end

  def preferred_host_image
    return unless user.present?
    @preferred_host_image ||= user.codespace_preferred_host_image
  end

  def vscode_channel
    return unless user.present?
    @vscode_channel ||= user.codespace_vscode_channel
  end

  def default_location
    return unless user.present?
    return @default_location if defined?(@default_location)
    @default_location = user.codespace_default_location
  end

  def default_idle_timeout
    return unless user.present?
    return @default_idle_timeout if defined?(@default_idle_timeout)
    @default_idle_timeout = user.codespace_default_idle_timeout
  end

  def default_retention_period
    return unless user.present?
    return @default_retention_period if defined?(@default_retention_period)
    @default_retention_period = user.codespace_default_retention_period
  end

  def telemetry_level
    return unless user.present?
    @telemetry_level ||= user.codespace_default_telemetry_level
  end

  def settings_sync
    return unless user.present?
    @settings_sync = user.codespaces_settings_sync_authorization
  end

  def preferred_editor=(editor)
    @updates << :preferred_editor
    @preferred_editor = editor
  end

  def preferred_host_image=(host_image)
    @updates << :preferred_host_image
    @preferred_host_image = host_image
  end

  def vscode_channel=(channel)
    @updates << :vscode_channel
    @vscode_channel = channel
  end

  def default_location=(location)
    @updates << :default_location
    @default_location = location
  end

  def default_idle_timeout=(timeout)
    @updates << :default_idle_timeout
    @default_idle_timeout = timeout
  end

  def default_retention_period=(period)
    @updates << :default_retention_period
    @default_retention_period = period
  end

  def telemetry_level=(level)
    @updates << :telemetry_level
    @telemetry_level = level
  end

  def save(actor: nil)
    @changes = {} # Keep track of changes to the settings so we can respond to the setter.
    actor ||= user
    if valid?
      User.transaction do # We need to make sure we can rollback if we fail.
        user.update_codespace_vscode_channel(vscode_channel, actor: actor) if @updates.include?(:vscode_channel)
        user.update_codespace_preferred_editor(preferred_editor, actor: actor) if @updates.include?(:preferred_editor)
        user.update_codespace_preferred_host_image(preferred_host_image, actor: actor) if @updates.include?(:preferred_host_image)
        user.update_codespace_default_location(default_location, actor: actor) if @updates.include?(:default_location)
        user.update_codespace_default_idle_timeout(default_idle_timeout, actor: actor) if @updates.include?(:default_idle_timeout)
        user.update_codespace_default_retention_period(default_retention_period, actor: actor) if @updates.include?(:default_retention_period)
        user.update_codespace_default_telemetry_level(telemetry_level, actor: actor) if @updates.include?(:telemetry_level)
      end
      create_changed
      @updates.clear
      self
    else
      false
    end
  end

  def changes
    @changes || {}
  end

  # Update attributes wihtout saving.
  def write_attributes(attributes, actor: nil)
    update(attributes, actor: actor, write: false)
  end

  # Update and save attributes.
  def update(new_settings, actor: nil, write: true)
    # TODO set an actor and pass it on.
    new_settings.each do |key, value|
      send("#{key}=", value) if respond_to?("#{key}=")
    end
    save(actor: actor) if write
  end

  # Currently used by the workbench to pass the settings to the editor.
  def vscode_settings(codespaces_home_url: nil, default_extensions: DEFAULT_EXTENSIONS, github_token: nil, user: nil, open_files_specified: nil)
    extensions = default_extensions.map { |e| { "id": e } }

    {
      vscodeChannel: vscode_channel,
      enableSyncByDefault: false,
      # Used to display the home icon in the workbench.
      homeIndicator: {
        icon: "github-inverted",
        href: codespaces_home_url,
        title: "Go Home",
      },
      defaultSettings: default_settings(open_files_specified:),
      defaultExtensions: extensions,
      defaultAuthSessions: auth_sessions(github_token),
      authenticationSessionId: "github-session-sync-service",
      settingsSync: settings_sync,
    }.deep_merge(color_mode_settings)
  end

  def prefers_non_web_editor?
    WEB_EDITORS.exclude?(preferred_editor)
  end

  private

  def default_settings(open_files_specified:)
    # Use the Enterprise auth provider in development because it lets us customize the API URL the extension will use.
    auth_provider_settings = if GitHub.multi_tenant_enterprise? || Rails.env.development?
      {
        "github.codespaces.authProvider": "github-enterprise",
        "github-enterprise.uri": GitHub.url,
      }
    else
      {
        "github.codespaces.authProvider": "github",
      }
    end

    {
      "workbench.startupEditor": open_files_specified ? "none" : "readme",
      "telemetry.telemetryLevel": telemetry_level,
      **auth_provider_settings,
    }
  end

  def auth_sessions(token)
    # We need to provide an auth session for each of the built-in extensions
    # which exactly matches the scopes that they request. If an extension asks
    # for a set of scopes that we don't provide then VS Code will send them
    # through the auth server flow.
    [
      {
        type: "github",
        id: "github-session-sync-service",
        accessToken: token,
        account: {
          id: user.id.to_s,
          label: @user.display_login
        },
        scopes: ["user:email"],
      },
      {
        # Codespaces extension: https://github.com/github/codespaces-vscode/blob/4dfcfda6e335000a6756eabb9972f2692ddbafdf/src/codespaces/src/authentication/githubAuthentication.ts#L7
        type: "github",
        id: "github-session-codespaces-extension",
        accessToken: token,
        account: {
          id: user.id.to_s,
          label: @user.display_login
        },
        scopes: ["read:user", "user:email", "repo", "codespace"].sort
      },
      {
        # Used by GH Pull Request, GH Repository, and Codespaces extensions.
        # This is being deprecated as we move these extenstions to github-session-ghpr-ghr and github-session-codespaces-extension below to support additional scopes.
        # Full removal is blocked by https://github.com/github/codespaces/issues/7142
        # GHPR extension: https://github.com/microsoft/vscode-pull-request-github/blob/861b56494f2dceb8930db1f13f3e3c273b095f8d/src/github/credentials.ts#L28
        # Codespaces extension: https://github.com/github/codespaces-vscode/blob/4dfcfda6e335000a6756eabb9972f2692ddbafdf/src/codespaces/src/authentication/githubAuthentication.ts#L7
        type: "github",
        id: "github-session-vs-codespaces",
        accessToken: token,
        account: {
          id: user.id.to_s,
          label: @user.display_login
        },
        scopes: ["read:user", "user:email", "repo"].sort
      },
      {
        # Used by GH Pull Request and GH Repository extensions.
        # Migration issue: https://github.com/github/codespaces/issues/7456
        # GHPR extension scopes: https://github.com/microsoft/vscode-pull-request-github/blob/861b56494f2dceb8930db1f13f3e3c273b095f8d/src/github/credentials.ts#L28
        # GHR extention scopes: https://github.com/microsoft/vscode-remotehub/blob/948587fcb0bfbf8b03226bfc393bb63f7dcceb40/extensions/github/src/provider.ts#L98
        type: "github",
        id: "github-session-ghpr-ghr",
        accessToken: token,
        account: {
          id: user.id.to_s,
          label: @user.display_login
        },
        scopes: ["read:user", "user:email", "repo", "workflow"].sort
      },
      {
        # Copilot extension: https://github.com/github/copilot/blob/74401f500904759d4ab98d3e9e9f3bda2023efdd/src/session.ts#L4
        type: "github",
        id: "github-session-github-copilot",
        accessToken: token,
        account: {
          id: user.id.to_s,
          label: @user.display_login
        },
        scopes: ["read:user"],
      },
      {
        # VS Code GitHub auth: https://github.com/microsoft/vscode/blob/9921c378a0006f14b0386ae2e531058c9363ef72/extensions/github/src/auth.ts#L27
        type: "github",
        id: "github-session-vs-code-auth",
        accessToken: token,
        account: {
          id: user.id.to_s,
          label: @user.display_login
        },
        scopes: %w[repo workflow],
      },
    ]
  end

  # Called when we save the settings, so we can create a changed hash.
  def create_changed
    @changes = @updates.inject({}) do |changes, attr|
      changes[attr] = send(attr) if respond_to?(attr)
      changes
    end
  end

  LIGHT_THEME = "GitHub Light Default"
  DARK_THEME  = "GitHub Dark Default"
  LEGACY_THEME_SETTINGS = { defaultSettings: { "workbench.colorTheme": LIGHT_THEME } }
  DARK_MODE_SETTINGS = {
    loadingScreenThemeColor: "dark",
    defaultSettings: {
      "workbench.colorTheme": DARK_THEME
    }
  }
  LIGHT_MODE_SETTINGS = {
    loadingScreenThemeColor: "light",
    defaultSettings: {
      "workbench.colorTheme": LIGHT_THEME
    }
  }
  def color_mode_settings
    if user.color_mode_with_default.dark?
      DARK_MODE_SETTINGS
    elsif user.color_mode_with_default.light?
      LIGHT_MODE_SETTINGS
    else
      # If the user is on 'auto' don't pass _any_ settings to VSCode
      # so it can track the user's system settings like GitHub does.
      {}
    end
  end
end
