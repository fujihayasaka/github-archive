# typed: true
# frozen_string_literal: true

# IMPORTANT: This file is run after every db:migrate and needs to be idempotent.
require "github/dgit/sql"

if Rails.env.development?
  require "aqueduct_lite_process_helper"
  AqueductLiteProcessHelper.ensure_jobs_can_enqueue

  require_relative "../script/seeds/runners/billing_product_uuids"
  Seeds::Runner::BillingProductUUIDs::PRODUCT_TYPES.values.each do |product_type|
    Seeds::Runner::BillingProductUUIDs.run(product_type: product_type) # rubocop:disable Lint/ExecuteSeedRunners
  end

  unless User.ghost.present?
    User.create_ghost
  end

  mona = User.find_by(login: "monalisa")
  unless mona.present?
    mona = User.create(login: "monalisa",
                       password: GitHub.default_password,
                       email: "octocat@github.com",
                       require_email_verification: false,
                       billing_attempts: 0,
                       plan: GitHub::Plan.pro)
    mona.emails.map(&:verify!)
  end

  # for dev setup automation we ensure an all-powerful PAT exists for the mona user
  token_suffix = "MonalisaTheOctoPatMonalisaTheOctoPat"
  predetermined_token = "ghp_#{token_suffix}"
  hashed_token = OauthAccessTokens::Domain.hash_token(predetermined_token)
  unless !OauthAccessTokens.domain.user_access_by_hash(mona.id, hashed_token).nil?
    scopes = Api::AccessControl.scopes.select { |_name, scope| scope.grantable? && scope.parent.nil? }.keys
    scopes = scopes.reject { |scope| scope == "site_admin" } if GitHub.enterprise? # this is inelegant, not sure if there's a better way to exclude scopes that are not compatible with enterprise
    access = mona.oauth_accesses.create! do |acc|
      acc.application_id = ::OauthApplication::PERSONAL_TOKENS_APPLICATION_ID
      acc.application_type = ::OauthApplication::PERSONAL_TOKENS_APPLICATION_TYPE
      acc.description = "Fixed db/seed.rb PAT <PAT_PREFIX>_#{token_suffix}"
      acc.scopes = OauthAccessTokens::Domain.normalize_scopes(scopes, visibility: :all)
    end

    ActiveRecord::Base.connected_to(role: :writing) do
      OauthAccess.connection.update(Arel.sql(<<-SQL, id: access.id, hashed_token: OauthAccessTokens::Domain.hash_token(predetermined_token), token_last_eight: predetermined_token.last(8), expires_at_timestamp: 1.year.from_now.to_i))
      UPDATE oauth_accesses
        SET
          hashed_token = :hashed_token,
          token_last_eight = :token_last_eight,
          updated_at = now(),
          expires_at_timestamp = :expires_at_timestamp
          WHERE
          id = :id
      SQL
    end
  end

  web_flow = User.find_by(login: "web-flow")
  unless web_flow.present?
    web_flow = User.create(login: "web-flow",
                           password: GitHub.default_password,
                           email: GitHub.web_committer_email,
                           require_email_verification: false,
                           billing_attempts: 0,
                           plan: GitHub::Plan.pro)
    web_flow.emails.map(&:verify!)
    GpgKey.connection.insert(Arel.sql(<<-SQL, user_id: web_flow.id, email: GitHub.web_committer_email, now: Time.now))
      INSERT INTO gpg_keys (
        user_id, key_id, public_key, created_at, updated_at, can_certify, raw_key
      ) VALUES (
        :user_id,
        x'08a088acef151af6',
        x'c6c04d0459946841010800b8eb86e801a93f15cb8f158bfd91625e307ea4d7510a0719f15ade7b770f4075866068c7115790fa9c25c2f25653fab80ad5f566145cec5e8978d83f89a6995869230cc5d20d728e36e10fd274640ed6af1747d2c40d5b88f2f914679152e259ff50ce7bd62f9819dd81e39e85a310b816ca659c9faf62d015afccfa38b465b513decbecacb99dffbd56c79b2a928b55c78a4fb2f8dafa9bbf1d58c84d2cb8376f110beb3a54178eff6c904b3c35d39abfe961b7b48da63034d1f3c46d00b738d0e5fd57d6a9284ab36831238cb78827d70020bc56d518af8acd06760a01857ee05e6cd4d0ddc6a1327decca593637ad6bde554ad5f0fb9ee373bd9ed69f51c10011010001',
        :now,
        :now,
        '1',
        '-----BEGIN PGP PUBLIC KEY BLOCK-----\n\nxsBNBFmUaEEBCAC464boAak/FcuPFYv9kWJeMH6k11EKBxnxWt57dw9AdYZgaMcR\nV5D6nCXC8lZT+rgK1fVmFFzsXol42D+JpplYaSMMxdINco424Q/SdGQO1q8XR9LE\nDVuI8vkUZ5FS4ln/UM571i+YGd2B456FoxC4FsplnJ+vYtAVr8z6OLRltRPey+ys\nuZ3/vVbHmyqSi1XHik+y+Nr6m78dWMhNLLg3bxEL6zpUF47/bJBLPDXTmr/pYbe0\njaYwNNHzxG0AtzjQ5f1X1qkoSrNoMSOMt4gn1wAgvFbVGK+KzQZ2CgGFfuBebNTQ\n3cahMn3sylk2N61r3lVK1fD7nuNzvZ7Wn1HBABEBAAHNNUdpdEh1YiAod2ViLWZs\nb3cgY29tbWl0IHNpZ25pbmcpIDxub3JlcGx5QGdpdGh1Yi5jb20+wsBiBBMBCAAW\nBQJZlGhBCRAIoIis7xUa9gIbAwIZAQAAmQEIABaVA6Loqv2gTFmyKFH5R7u0MQhQ\n5NADAxbEeGEEBAh7OgBaEDOIe7QdXK43qQeWGLBroiDcILEYG+URFG5JtNUGoQza\nstFvnFu9fZC7eV6iE2QVf43RIkXvSDh4c87vonvLKcEWSz/KT9jATVAGkLxY0lDw\nWeCnoJTgP9oSR1vR6g5uJEwrFNIjkdHyMX2GD0Nz6OU1Pzu3qvaV7zd9eHqkAV4+\n+o8600c6LHj5uzIGOGxnTDaMOzqKub69i+DLEQKm8Nhq5uu9DMM6Nkr4ikU4Wfw6\nVTNz0I3RK2iXAlbDm2nyr/LndvRZlx0byZGFqL8GEYi/Okvq23ooPxt++9s=\n=aphP\n-----END PGP PUBLIC KEY BLOCK-----'
      )
    SQL
    GpgKeyEmail.connection.insert(Arel.sql(<<-SQL, email: GitHub.web_committer_email, user_email_id: T.must(web_flow.emails.first).id, gpg_key_id: web_flow.reload.gpg_keys.first.id))
      INSERT INTO gpg_key_emails (
        email, user_email_id, gpg_key_id
      ) VALUES (
        :email, :user_email_id, :gpg_key_id
      )
    SQL
  end

  bulwark_user = User.find_by(login: "bulwark-user")
  unless bulwark_user.present?
    bulwark_user = User.create(login: "bulwark-user",
                      password: GitHub.default_password,
                      email: "bulwark@github.com",
                      require_email_verification: false,
                      two_factor_requirement_metadata: TwoFactorRequirementMetadata.new({
                        interrupt_first_seen_at: Time.now.utc - 2.days,
                        required_by: Time.now.utc - 1.day,
                        requirement_reason: 1,
                        state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:required],
                        })
                      )
    bulwark_user.emails.map(&:verify!)
  end

  github = Organization.find_by(login: "github")
  unless github.present?
    github = Organization.create(login: "github",
                                 billing_email: "test-github-support@github.test.com",
                                 plan: GitHub::Plan.business_plus,
                                 seats: 1000,
                                 admin: mona)

    github.teams.create(name: "Employees").add_member(mona)
    GitHub::FeatureFlag.team_cache.clear
    mona.clear_employee_memo
    mona.update(gh_role: "staff")
    mona.stafftools_roles << StafftoolsRole.new(name: "super-admin")
  end

  github_business = Business.find_by(name: "GitHub, Inc")
  unless github_business.present?
    github_business = Business.create(
      name: "GitHub, Inc",
      seats: 1000,
      owners: [mona],
      organizations: [github],
      customer: Customer.create(
        billing_type: "invoice",
        billing_end_date: GitHub::Billing.today + 1.year,
        name: "GitHub, Inc",
        billing_attempts: 0,
        term_length: 12,
      ),
    )
    unless GitHub.enterprise?
      github_business.mark_advanced_security_as_purchased_for_entity(actor: mona)
      github_business.set_advanced_security_seats_for_entity(seats: 0, actor: mona)
    end
  end


  category = Marketplace::Category.find_by(name: "Default Category")
  unless category.present?
    Marketplace::Category.create(
      name: "Default Category",
      description: "The default marketplace app category.",
      navigation_visible: true,
    )
  end

  GitHub::DGit::SpokesSQL.run <<-SQL
    REPLACE INTO datacenters (datacenter, region)
    VALUES ("dc1", "region1"),
      ("dc2", "region2")
  SQL

  GitHub::DGit::SpokesSQL.run <<-SQL
    REPLACE INTO fileservers (host, fqdn, online, rack, datacenter, site, non_voting)
    VALUES ("dgit1", "dgit1.", 1, "ab1", "dc1", "dc1-iad", 0),
      ("dgit2", "dgit2.", 1, "ab2", "dc1", "dc1-iad", 0),
      ("dgit3", "dgit3.", 1, "ab3", "dc1", "dc1-iad", 0),
      ("dgit4", "dgit4.", 1, "ab4", "dc1", "dc1-iad", 0),
      ("dgit5", "dgit5.", 1, "n1", "dc2", "dc2-sea", 0)
  SQL

  Page::FileServer.connection.execute <<-SQL
    TRUNCATE TABLE pages_fileservers
  SQL

  Page::FileServer.connection.execute <<-SQL
    REPLACE INTO pages_fileservers (host, online, embargoed, disk_free, disk_used, created_at, updated_at)
    VALUES ("localhost", 1, 0, 100000, 0, NOW(), NOW())
  SQL

  (0..7).each do |partition|
    Page::Partition.connection.insert(Arel.sql(<<-SQL, partition: partition.to_s(16)))
      REPLACE INTO pages_partitions (`host`, `partition`, `disk_free`, `disk_used`, `created_at`, `updated_at`)
      VALUES ("localhost", :partition, 1000000, 0, NOW(), NOW())
    SQL
  end

  unless Survey.connection.select_values(Arel.sql("SELECT id FROM surveys WHERE slug = :slug", slug: "org_downgrade")).present?
    require "github/transitions/20150819185447_org_downgrade_survey"
    transition = GitHub::Transitions::OrgExitSurvey.new
    transition.perform
  end

  unless Survey.where(slug: "per_seat_org_downgrade").exists?
    require "github/transitions/20160607211429_per_seat_downgrade_survey"
    GitHub::Transitions::PerSeatDowngradeSurvey.new.perform
  end

  unless Survey.where(slug: "user_identification").exists?
    require "github/transitions/20190405113134_add_user_onboarding_survey"
    GitHub::Transitions::AddUserOnboardingSurvey.new(dry_run: false).perform
  end

  unless SurveyQuestion.where(short_text: "user_role").exists?
    require "github/transitions/20200210160651_add_role_question_to_user_identification_survey"
    GitHub::Transitions::AddRoleQuestionToUserIdentificationSurvey.new(dry_run: false).perform
  end

  unless Survey.where(slug: "per_seat_org_downgrade_text_only").exists?
    require "github/transitions/20200124160135_add_per_seat_org_downgrade_text_only_survey"
    GitHub::Transitions::AddPerSeatOrgDowngradeTextOnlySurvey.new(dry_run: false).perform
  end

  unless SurveyQuestion.where(short_text: "organization_id", survey_id: Survey.where(slug: "per_seat_org_downgrade_text_only").last&.id).exists?
    require "github/transitions/20200316181412_add_organization_id_question_to_downgrade_survey"
    GitHub::Transitions::AddOrganizationIdQuestionToDowngradeSurvey.new(dry_run: false).perform
  end

  unless Survey.where(slug: "code_scanning").exists?
    require "github/transitions/20200324185251_create_code_scanning_waitlist_survey"
    GitHub::Transitions::CreateCodeScanningWaitlistSurvey.new(dry_run: false).perform
  end

  unless Survey.find_by(slug: "code_scanning")&.questions&.find_by(short_text: "private_repositories").present?
    require "github/transitions/20200416134656_add_private_repository_advanced_security_survey_question"
    GitHub::Transitions::AddPrivateRepositoryAdvancedSecuritySurveyQuestion.new(dry_run: false).perform
  end

  unless Survey.where(slug: "workspaces").exists?
    require "github/transitions/20200403135139_create_workspaces_signup_survey"
    GitHub::Transitions::CreateWorkspacesSignupSurvey.new(dry_run: false).perform
    require "github/transitions/20200428140122_update_workspaces_signup_survey_choices"
    GitHub::Transitions::UpdateWorkspacesSignupSurveyChoices.new(dry_run: false).perform
    require "github/transitions/20200903133800_update_workspaces_signup_survey_add_development_environment_question"
    GitHub::Transitions::UpdateWorkspacesSignupsSurveyAddDevelopmentEnvironmentQuestion.new(dry_run: false).perform
    require "github/transitions/20200903140700_update_workspaces_signup_survey_reorder_choices"
    GitHub::Transitions::UpdateWorkspacesSignupsSurveyReorderChoices.new(dry_run: false).perform
  end

  unless Survey.where(slug: "codespaces_vs2019").exists?
    require "github/transitions/20200914164004_create_codespaces_vs2019_signup_survey"
    GitHub::Transitions::CreateCodespacesVs2019SignupSurvey.new(dry_run: false).perform
  end

  unless Survey.where(slug: "okta_team_sync").exists?
    require "github/transitions/20200504234046_create_okta_team_sync_beta_signup_survey"
    GitHub::Transitions::CreateOktaTeamSyncBetaSignupSurvey.new(dry_run: false).perform
  end

  unless Survey.where(slug: "org_creation").exists?
    require "github/transitions/20160628220736_add_org_creation_survey"
    GitHub::Transitions::AddOrgCreationSurvey.new.perform
    require "github/transitions/20200519233106_update_org_creation_survey"
    GitHub::Transitions::UpdateOrgCreationSurvey.new(dry_run: false).perform
    require "github/transitions/20211208215822_update_org_creation_survey_size_range"
    GitHub::Transitions::UpdateOrgCreationSurveySizeRange.new(dry_run: false).perform
  end

  unless Survey.where(slug: "projects_vnext").exists?
    require "github/transitions/20210601190848_create_projects_v_next_survey"
    GitHub::Transitions::CreateProjectsVNextSurvey.new(dry_run: false).perform
  end

  unless Survey.where(slug: "repositories_survey").exists?
    require "github/transitions/20220510134858_create_repos_survey"
    GitHub::Transitions::CreateReposSurvey.new(dry_run: false).perform
    require "github/transitions/20220520083721_repositories_survey_add_question"
    GitHub::Transitions::RepositoriesSurveyAddQuestion.new(dry_run: false).perform
    require "github/transitions/20220520131556_repos_survey_fix_typo"
    GitHub::Transitions::ReposSurveyFixTypo.new(dry_run: false).perform
  end

  Storage::FileServer.connection.execute <<-SQL
    REPLACE INTO storage_file_servers (host, online, embargoed, created_at, updated_at)
    VALUES ("localhost", 1, 0, NOW(), NOW())
  SQL

  PreReceiveEnvironment.connection.execute <<-SQL
    REPLACE INTO pre_receive_environments (id, name, image_url, checksum, created_at, updated_at)
    VALUES (1, 'Default', 'githubenterprise://internal', '0', NOW(), NOW())
  SQL

  if GitHub.gist_oauth_client_id && GitHub.gist_oauth_secret_key &&
    !OauthApplication.find_by_key(GitHub.gist_oauth_client_id).present?
    github = Organization.find_by(login: "github")
    app = OauthApplication.create(name: "gist",
                            user: github,
                            url: "http://#{GitHub.gist3_host_name}",
                            callback_url: "http://#{GitHub.gist3_host_name}/auth/github/callback",
                            key: GitHub.gist_oauth_client_id,
                            domain: GitHub.gist3_host_name)
    app.client_secrets.create(creator: User.ghost, secret_hash: OauthApplicationClientSecret.hash_for(GitHub.gist_oauth_secret_key),
                              secret_last_eight: GitHub.gist_oauth_secret_key.last(8))
    app
  end

  unless OauthApplication.find_by_key(Apps::Privileged::GitHubCLI::GITHUB_CLI_CLIENT_ID).present?
    OauthApplication.create(
      name: "GitHub CLI",
      user: Organization.find_by(login: "github"),
      url: "https://cli.github.com",
      callback_url: "http://127.0.0.1/callback",
      key: Apps::Privileged::GitHubCLI::GITHUB_CLI_CLIENT_ID,
      device_flow_enabled: true,
    )
  end

  # Create FGP preset roles and permissions data
  GitHub.system_roles.reconcile(purge: true)

  # Create a feature preview and associated flags
  Seeds::Objects::FeatureFlag.enable(feature_flag: "test_toggleable_feature")
  test_feature = FlipperFeature.find_by(name: "test_toggleable_feature")
  if !Feature.find_by(slug: "test_toggleable_feature")
    Feature.create(
      public_name: "Test Toggleable Feature",
      slug: "test_toggleable_feature",
      flipper_feature_id: T.must(test_feature).id,
      description: "A test toggleable feature, to test Feature Preview.",
      feedback_link: GitHub.support_url,
    )
  end

  # Create a feature flag for viewing feature flags in devtools
  Seeds::Objects::FeatureFlag.enable(feature_flag: "devtools_feature_flags_disabled_exclusion")

  # Create the command palette feature flag and associated feature preview
  Seeds::Objects::FeatureFlag.enable(feature_flag: "command_palette")
  command_palette_feature = FlipperFeature.find_by(name: "command_palette")
  if !Feature.find_by(slug: "command_palette")
    Feature.create(
      public_name: "Command palette",
      slug: "command_palette",
      flipper_feature_id: T.must(command_palette_feature).id,
      feedback_link: "https://github.com/github/design-infrastructure/discussions/1521",
      enrolled_by_default: true
    )
  end

  # Create the slash commands feature flags
  Seeds::Objects::FeatureFlag.enable(feature_flag: "slash_commands")

  # Enable the user defined commands feature flag
  Seeds::Objects::FeatureFlag.enable(feature_flag: "user_defined_commands")

  # Enable octocaptcha in development
  Seeds::Objects::FeatureFlag.enable(feature_flag: "octocaptcha")

  # Create webhook for the github org
  hook = Hook.find_by(creator_id: mona.id, name: "web", active: true, installation_target: github)
  unless hook
    hook = Hook.new(creator_id: mona.id, name: "web", active: true, installation_target: github)
    hook_config = {
      url: "https://smee.io/FswqyFrCh4Vxx8jL",
      content_type: "json"
    }
    hook.configure_with(true, hook_config)
  end

  unless CWE.exists?
    require "github/transitions/20201027190230_backfill_cwe_data"
    GitHub::Transitions::BackfillCWEData.new(dry_run: false).perform
  end

  VulnerabilityAlertRule.create_default_auto_dismissal_rule

  # we do not have the GHR on enterprise
  SecurityConfiguration.create_github_recommended_configuration unless GitHub.enterprise?

  # ensure code scanning app is created
  Apps::Privileged::CodeScanning.seed_database! unless GitHub.enterprise?

  # ensure campaigns app is created
  Apps::Privileged::Campaigns.seed_database! unless GitHub.enterprise?

  # grant write permissions to organization projects to org members
  memex_org_access_entry = Configuration::Entry.memex_project_org_wide_role.global.take

  unless memex_org_access_entry.present?
    Configuration::Entry.memex_project_org_wide_role.global.create(
      value: "project_writer",
      updater: User.find_by(login: "monalisa"),
    )
  end

  # ensure memex automation app is created
  Apps::Privileged::MemexAutomation.seed_database! unless GitHub.enterprise?

  Apps::Privileged::MergeQueue.seed_database! unless GitHub.enterprise?

  Apps::Privileged::MergeCommitUpdateRefs.seed_database! unless GitHub.enterprise?

  Apps::Privileged::CopilotPullRequestReviewer.seed_database! unless GitHub.enterprise?

  unless GitHub.enterprise? || ENV["SKIP_IDENTITY_SEEDS"]
    # EMU Seed setup see db/identity_seed_data.yml file
    data = Seeds::Objects::SsoIdentityCodespaceData.load

    Seeds::Objects::SsoIdentityCodespaceBusiness.create(data.businesses_data)
    Seeds::Objects::SsoIdentityCodespaceUser.create(data.users_data, data)
    Seeds::Objects::SsoIdentityCodespaceOrganization.create(data.organizations_data, data)
    Seeds::Objects::SsoIdentityCodespaceExternalGroup.create(data.external_groups_data, data)
  end

  Seeds::Objects::FeatureFlag.enable(feature_flag: "two_factor_holiday_warning_banner")

  Seeds::Objects::FeatureFlag.enable(feature_flag: "react_code_view_enabled")

  Seeds::Objects::FeatureFlag.enable(feature_flag: "bulwark_two_factor_required_feature")

  # Copilot feature flags
  Seeds::Objects::FeatureFlag.enable(feature_flag: "copilot_limit_free_user_zero_step_signup")
end
