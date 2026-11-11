# typed: true
# frozen_string_literal: true

# Counterpart to GeneratedPathHelpersModule in         rbi/dsl/generated_path_helpers_module.rbi
# Note: Keep in sync with GeneratedUrlHelpersModule in rbi/shims/generated_url_helpers_module.rbi
module GeneratedPathHelpersModule
  # Defined in config/routes/enterprise.rb
  # These routes are defined behind a guard for GitHub.licensed_mode?
  sig { params(args: T.untyped).returns(String) }
  def settings_license_enterprise_path(*args); end

  # Defined in config/routes.rb
  # These routes are defined behind a guard for GitHub.enterprise?
  sig { params(args: T.untyped).returns(String) }
  def dotcom_search_path(*args); end

  # Defined in config/routes/stafftools.rb
  # Stafftools route for Copilot policy cache management
  sig { params(args: T.untyped).returns(String) }
  def stafftools_copilot_policies_path(*args); end

  # Defined in config/routes/stafftools.rb
  # Stafftools route for Copilot rules resync
  sig { params(args: T.untyped).returns(String) }
  def stafftools_copilot_rules_resync_index_path(*args); end

  # Defined in config/routes.rb
  sig { params(args: T.untyped).returns(String) }
  def organization_in_product_messaging_path(*args); end

  # Defined in config/routes/enterprises.rb
  sig { params(args: T.untyped).returns(String) }
  def settings_in_product_messaging_enterprise_path(*args); end

  # Defined in config/routes/copilot.rb
  sig { params(args: T.untyped).returns(String) }
  def settings_org_copilot_code_review_path(*args); end

  # Defined in config/routes/copilot.rb
  sig { params(args: T.untyped).returns(String) }
  def settings_org_copilot_code_review_update_path(*args); end

  # Defined in config/routes/copilot.rb
  sig { params(args: T.untyped).returns(String) }
  def settings_org_copilot_code_review_approval_repository_items_path(*args); end

  # Defined in repository routes
  sig { params(args: T.untyped).returns(String) }
  def repo_code_review_repository_qualified_approval_settings_path(*args); end

  # Defined in config/routes/enterprises.rb
  sig { params(args: T.untyped).returns(String) }
  def settings_sandboxes_enterprise_path(*args); end

  # Defined in config/routes/enterprises.rb
  sig { params(args: T.untyped).returns(String) }
  def update_settings_sandbox_enablement_enterprise_path(*args); end
end
