#!/usr/bin/env safe-ruby
# frozen_string_literal: true

require "base64"
require "securerandom"
require_relative "../config/environment"

class LoopsSetup
  attr_reader :envvars

  def initialize
    @envvars = {}
  end

  def run
    enable_feature_flags
    enable_loops_policy
    enable_claude_policy
    integration = seed_github_app
    setup_environment_variables(integration)
    write_env_file
    puts "\n🎉 Loops setup complete!"
  end

  private

  def mona
    @mona ||= User.find_by_login("monalisa")
  end

  def enable_loops_policy(org: "github", user: mona)
    organization = Organization.find_by_login(org)
    copilot_org = Copilot::Organization.new(organization)
    copilot_business = copilot_org.copilot_business

    # Enable Copilot for the business and upgrade it to the enterprise plan
    copilot_business.enable_copilot_for_all_organizations!(user)
    copilot_business.copilot_plan_enterprise!

    # Give monalisa a Copilot seat
    copilot_org.seat_management_allow_all!(user)

    copilot_business.configuration.loops_enabled!
    puts "  ✅ Enabled Loops policy for Github"
  end

  def enable_claude_policy(org: "github", user: mona)
    organization = ::Organization.find_by(login: org)
    copilot_org = Copilot::Organization.new(organization)
    copilot_business = Copilot::Business.new(copilot_org.business)

    unless Copilot::Policies::Models::Afos.available_for?(copilot_business)
      puts "⚠️  Claude Sonnet 4 not available for enterprise: #{copilot_business.name}"
      return
    end

    Copilot::Policies::Models::Afos.update_business(copilot_business, "enabled")

    puts "✅ Enabled Sonnet policy for GitHub"
  end

  def enable_feature_flags
    feature_flags = %w[
      copilot_pipes
      copilot_pipes_github_graphql_nodes
      copilot_loops_post_staff_ship_features
      copilot_loops_share_button
      loops_public_graphql_api
      loops_graphql_reauth_query
      copilot_api_enable_model_claude_afos_anthropic
    ]

    puts "Enabling #{feature_flags.length} feature #{'flag'.pluralize(feature_flags.length)}:"
    puts

    feature_flags.each do |feature_flag|
      FeatureFlag.vexi_management.enable_feature_flag(feature_flag)

      if FeatureFlag.vexi.enabled?(feature_flag, default: false)
        puts "  ✅ #{feature_flag} enabled"
      else
        puts "  ❌ #{feature_flag} could not be enabled"
      end
    end
    puts
  end

  def seed_github_app
    puts "➡️ Setting up Loops GitHub App..."

    # First try to find existing integration
    integration = Apps::Privileged.integration(:loops)

    if integration.nil?
      puts "📝 Creating new Loops GitHub App..."
      integration = Apps::Privileged::Loops.seed_database!
    else
      puts "✅ Found existing Loops GitHub App"
    end

    if integration.nil?
      puts "❌ Failed to seed or find Loops GitHub App"
      exit 1
    end

    puts "✅ Loops GitHub App ready (ID: #{integration.id})"
    integration
  end

  def setup_environment_variables(integration)
    puts "➡️ Setting up environment variables..."

    # Generate private key
    key = integration.generate_key(creator: mona).private_key.to_pem

    add_env_vars({
      "GITHUB_APP_ID" => integration.id.to_s,
      "GITHUB_APP_PRIVATE_KEY" => Base64.strict_encode64(key.strip),
      "GITHUB_APP_TARGET_ID" => "1",
      "GITHUB_GRAPHQL_API_URL" => "http://api.github.localhost/graphql",
      "MONOLITH_TWIRP_LOOPS_URL" => "http://api.github.localhost/internal",
      "API_INTERNAL_TWIRP_HMAC_KEYS_FOR_LOOPS" => "loopshmac"
    })
  end

  def generate_simple_box_key
    # Generate a 32-byte key for NaCl SimpleBox (base64 encoded)
    Base64.strict_encode64(SecureRandom.bytes(32))
  end

  def write_env_file
    env_path = "/workspaces/loops/.env"
    puts "\n➡️ Updating #{env_path} with environment variables"

    # Read existing .env file if it exists
    existing_vars = {}
    if File.exist?(env_path)
      puts "📖 Reading existing environment variables..."
      File.readlines(env_path).each do |line|
        line = line.strip
        # Skip empty lines and comments
        next if line.empty? || line.start_with?("#")
        # Parse KEY=VALUE format
        if line.include?("=")
          key, value = line.split("=", 2)
          # Remove quotes if present
          value = value.gsub(/^["']|["']$/, "") if value
          existing_vars[key] = value
        end
      end
      puts "✅ Found #{existing_vars.length} existing variables"
    end

    # Merge existing variables with new ones (new ones take precedence)
    final_vars = existing_vars.merge(envvars)

    # Build final content
    content_lines = final_vars.map { |k, v| "#{k}=\"#{v}\"" }
    content = content_lines.join("\n")

    puts content

    File.write(env_path, content)
    puts "\n✅ Environment file updated at #{env_path}"
  end

  def add_env_vars(vars)
    envvars.merge!(vars)
  end
end

LoopsSetup.new.run
