# typed: true
# frozen_string_literal: true

require "socket"
require "json"
require "digest/sha2"
require "audit/context"

class GitHub::HookContext
  attr_reader :config
  attr_reader :pusher
  attr_reader :proto
  attr_reader :path
  attr_accessor :audit_msg
  attr_reader :git_dir
  attr_reader :current_ref

  # Create a HookContext, setting up important state from the environment.
  # Also sets up Failbot and GitHub.context with default state.
  def initialize
    @config = if sockstat_var("repo_config")
      JSON.parse(sockstat_var("repo_config"))
    else
      {}
    end

    # A pusher is not assured in development mode, but
    # our Lord Maddox is always in our hearts.
    if Rails.env.development?
      ENV["GIT_PUSHER"] ||= ENV["GIT_SOCKSTAT_VAR_user_login"] || "maddox"
    end

    # Figure out some stuff from the environment
    @pusher    = sockstat_var(:user_login) || sockstat_var(:pubkey_verifier_login) || ENV["GIT_PUSHER"]
    @path      = ENV["REPO_PATH"]
    @audit_msg = ENV["AUDIT_MSG"]

    if sockstat_var(:pubkey_fingerprint)
      @proto = "ssh"
    else
      @proto = "http"
    end

    @git_dir = ENV["GIT_DIR"]

    @current_ref = GitHub.current_ref

    configure_failbot
    configure_context
  end

  # Read a SOCKSTAT variable. These are passed down the stack by each git
  # protocol and include extra info about the operation. See GitHub::RepoPermissions
  # for available var names.
  def sockstat_var(name)
    name = name.to_s
    value = ENV["GIT_SOCKSTAT_VAR_#{name}"]        ||
            ENV["GIT_SOCKSTAT_VAR_#{name.upcase}"] ||
            ENV["HTTP_X_SOCKSTAT_#{name}"]         ||
            ENV["HTTP_X_SOCKSTAT_#{name.upcase}"]

    case value
    when /bool:(true|false)/
      $1 == "true"
    when /uint:(\d+)/
      $1.to_i
    else
      value
    end
  end

  # Report an error to failbot and exit non-zero after giving the pusher some info
  # on what happened.
  #
  # boom       - An exception.
  # error_code - The simple error code that identifies this receive process.
  def die(boom, error_code)
    warn "Unexpected system error after push was received."
    warn "These changes may not be reflected on #{GitHub.host_name}!"
    warn "Your unique error code: #{error_code}" if error_code
    if %w[development test].include?(Rails.env)
      warn "#{boom.class}: #{boom.message}"
      warn boom.backtrace&.join("\n")
    else
      Failbot.report(boom, error_code: error_code)
    end
    exit! 1
  end

  def mode_error(**modes)
    modes = modes.map { |k, v| "#{k}=#{v}" }.join(", ")
    msg = "Unexpected pre-receive hook mode: #{modes}"
    die RuntimeError.new(msg), error_code
  end

  def repo_name
    sockstat_var(:repo_name)
  end

  def repo_id
    sockstat_var(:repo_id)
  end

  def check_lfs_integrity?
    !!sockstat_var(:check_lfs_integrity)
  end

  def gist?
    ENV["GIST_REPO"] == "1"
  end

  # Figure out the URL for the current repository.
  def repository_url
    if proto_is_ssh
      "git@#{GitHub.host_name}:#{repo_name}.git"
    else
      "https://#{GitHub.host_name}/#{repo_name}.git"
    end
  end

  def user_has_push_access?
    sockstat_var(:user_push_access)
  end

  def user_login
    sockstat_var(:user_login)
  end

  def user_has_operator_mode?
    sockstat_var(:user_operator_mode)
  end

  def pre_receive_hooks_overflow?
    sockstat_var(:repo_pre_receive_hooks) == GitHub::PreReceiveHookEntry::OVERFLOW
  end

  def pre_receive_hooks
    if hooks = sockstat_var(:repo_pre_receive_hooks)
      JSON.parse(hooks)
    else
      []
    end
  end

  def real_ip
    sockstat_var(:real_ip)
  end

  # A unique error code that we can send to failbot that's also given to
  # the user when an error occurs so they can include it with support requests.
  def error_code
    @error_code ||= begin
      hostname   = Socket.gethostname
      error_code = [hostname, $$, Time.now.to_f, "euH2baiMiGd"].join(":")
      error_code = Digest::SHA256.hexdigest(error_code)
      error_code
    end
  end

  def failbot_info
    info = {
      pusher: pusher,
      proto: proto,
      path: path,
      from: $PROGRAM_NAME,
      audit_msg: audit_msg,
    }
    if !GitHub.enterprise?
      info.update(
        env: Rails.env,
        current_ref: current_ref,
        error_code: error_code,
      )
    end
    info
  end

  private

  # Push a basic set of things onto the GitHub & Audit context
  def configure_context
    context = { from: $PROGRAM_NAME, pusher: pusher }
    GitHub.context.push(context)
    Audit.context.push(context)
  end

  def configure_failbot
    Failbot.push(failbot_info)
  end

  def proto_is_ssh
    @proto == "ssh"
  end
end
