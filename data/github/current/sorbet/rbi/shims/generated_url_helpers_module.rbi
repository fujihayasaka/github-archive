# typed: true
# frozen_string_literal: true

# Counterpart to GeneratedUrlHelpersModule in rbi/dsl/generated_url_helpers_module.rbi
#
# Note: Keep in sync with GeneratedPathHelpersModule in rbi/shims/generated_path_helpers_module.rbi
module GeneratedUrlHelpersModule
  # Defined in config/routes/enterprise.rb
  # These routes are defined behind a guard for GitHub.licensed_mode?
  sig { params(args: T.untyped).returns(String) }
  def settings_license_enterprise_url(*args); end

  # Defined in config/routes.rb
  # These routes are defined behind a guard for GitHub.enterprise?
  sig { params(args: T.untyped).returns(String) }
  def dotcom_search_url(*args); end

  # Defined in config/routes/copilot.rb
  sig { params(args: T.untyped).returns(String) }
  def settings_org_copilot_code_review_url(*args); end

  # Defined in config/routes/copilot.rb
  sig { params(args: T.untyped).returns(String) }
  def settings_org_copilot_code_review_update_url(*args); end

  # Defined in config/routes/copilot.rb
  sig { params(args: T.untyped).returns(String) }
  def settings_org_copilot_code_review_approval_repository_items_url(*args); end

  # Defined in repository routes
  sig { params(args: T.untyped).returns(String) }
  def repo_code_review_repository_qualified_approval_settings_url(*args); end

  # Defined in config/routes/enterprises.rb
  sig { params(args: T.untyped).returns(String) }
  def settings_sandboxes_enterprise_url(*args); end

  # Defined in config/routes/enterprises.rb
  sig { params(args: T.untyped).returns(String) }
  def update_settings_sandbox_enablement_enterprise_url(*args); end
end
