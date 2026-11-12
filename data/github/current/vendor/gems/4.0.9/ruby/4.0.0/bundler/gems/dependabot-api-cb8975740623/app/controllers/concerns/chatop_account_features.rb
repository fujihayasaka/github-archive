# frozen_string_literal: true

require "terminal-table"

module ChatopAccountFeatures
  extend ActiveSupport::Concern

  PERMITTED_ACCOUNT_FEATURES = (%w(
    global_tokens
    spammy
  ) + ChatopRepoFeatures::PERMITTED_REPO_FEATURES).freeze

  # rubocop:disable Metrics/BlockLength
  included do
    chatop :account_features,
           /account[-_\s]features\s+(?<github_login>.+)/,
           "account features LOGIN [--tenant TENANT] " \
           "- Retrieve the enabled features for the specified login" do
      github_login = jsonrpc_params[:github_login]
      if github_login.include?("enable ") || github_login.include?("disable ")
        jsonrpc_failure "Did you mean `.dependabot account feature #{github_login}`?"
        return
      end

      tenant = jsonrpc_params[:tenant]
      account = find_account!(github_login, tenant)
      features = PERMITTED_ACCOUNT_FEATURES.map do |feature|
        [feature, account.feature_enabled?(feature)]
      end

      table = Terminal::Table.new do |t|
        t.headings = %w(Feature Enabled?)
        t.rows = features
        t.align_column(1, :right)
        t.style = { border_top: false, border_bottom: false }
      end
      jsonrpc_success(["```", table.to_s, "```"].join("\n"))
    end

    chatop :account_feature_enable,
           /account[-_\s]feature[-_\s]enable\s+(?<github_login>\S+)\s+(?<feature>.+)/,
           "account feature enable LOGIN FEATURE [--tenant TENANT] " \
           "- Enable feature for the specified login" do
      github_login = jsonrpc_params[:github_login]
      feature = jsonrpc_params[:feature]

      unless PERMITTED_ACCOUNT_FEATURES.include? feature
        jsonrpc_failure "Feature `#{feature}` cannot be managed via chatops."
        return
      end

      tenant = jsonrpc_params[:tenant]
      account = find_account!(github_login, tenant)
      account.enable_feature(feature) # rubocop:disable Dependabot/NoLocalFeatureFlags
      jsonrpc_success "Successfully enabled `#{feature}` on `#{github_login}`"
    end

    chatop :account_feature_disable,
           /account[-_\s]feature[-_\s]disable\s+(?<github_login>\S+)\s+(?<feature>.+)/,
           "account feature disable LOGIN FEATURE [--tenant TENANT] " \
           "- Disable feature for the specified login" do
      github_login = jsonrpc_params[:github_login]
      feature = jsonrpc_params[:feature]

      unless PERMITTED_ACCOUNT_FEATURES.include? feature
        jsonrpc_failure "Feature `#{feature}` cannot be managed via chatops."
        return
      end

      tenant = jsonrpc_params[:tenant]
      account = find_account!(github_login, tenant)
      account.disable_feature(feature) # rubocop:disable Dependabot/NoLocalFeatureFlags
      jsonrpc_success "Successfully disabled `#{feature}` on `#{github_login}`"
    end
  end
  # rubocop:enable Metrics/BlockLength
end
