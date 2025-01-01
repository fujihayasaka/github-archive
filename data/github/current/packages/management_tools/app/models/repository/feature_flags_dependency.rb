# typed: true
# frozen_string_literal: true

# Allow us to set certain features based on if the repo is enabled for
# "preview_features" - this is most likely for private GitHub repos
#
# See app/models/user/feature_flag_methods.rb
# See also: http://martinfowler.com/bliki/FeatureToggle.html
module Repository::FeatureFlagsDependency
  extend T::Sig
  extend T::Helpers
  include GitHub::TokenScanning::TokenScanningPostProcessingHelper
  include GitHub::FlipperActor
  include GitHub::VexiActor

  def preview_features?
    T.bind(self, Repository)
    return false unless GitHub.preview_features_enabled?
    # These additional attribute checks help safe guard to return false instead of
    # ActiveModel::MissingAttributeError. Checking owner requires the owner_id
    # attribute to be set and checking if it is private requires the source_id
    # attribute to be set.
    self.has_attribute?(:owner_id) && self.has_attribute?(:source_id) && owner&.name == "github" && private?
  end

  # Public: Are discussion notifications disabled for this repository?
  def disable_discussions_notifications_flag_enabled?
    if defined?(@disable_discussions_notifications_flag_enabled)
      return @disable_discussions_notifications_flag_enabled
    end
    @disable_discussions_notifications_flag_enabled =
      # Only return true if the repository has been explicitly added to the
      # actor's list. This disables the ability to fully enable the feature,
      # removing the risk of disabling discussion notifications to all
      # repositories at once.
      GitHub.flipper[:disable_discussions_notifications].actors_value.include?(self.flipper_id)
  end

  # Public: Is adaptive card parsing enabled for this repository?
  def adaptive_card_parsing_enabled?
    return @adaptive_card_parsing_enabled if defined?(@adaptive_card_parsing_enabled)
    @adaptive_card_parsing_enabled = GitHub.flipper[:adaptive_card_markdown_parsing].enabled?(self)
  end

  def prerelease_feature_enabled?(name)
    T.bind(self, Repository)
    # Always disabled in Enterprise environments
    return false unless GitHub.preview_features_enabled?

    # If feature is explicitly enabled on this repo
    return true if GitHub.flipper[name].enabled?(self)

    # Always disable on public repos
    return false if public?

    # If the owner is opted in, enable for all of their private repos
    return true if private? && GitHub.flipper[name].enabled?(owner)

    # Otherwise the feature is disabled
    false
  end

  # Bounty hunters try to attack repositories under the @GitHubBounty org to
  # find security vulnerabilities. The GitHubBounty/welcome repository is
  # excluded because it's used for communication with bounty hunters.
  def bounty_hunter_target?
    T.bind(self, Repository)
    return false unless GitHub.preview_features_enabled?
    return false unless private?
    owner && T.unsafe(owner).name == "GitHubBounty" && name != "welcome"
  end

  # Does the current repository have languages supported by aleph indexing
  def alephd_indexing_enabled?
    alephd_language_indexing_enabled?
  end

  # Whether the current repository or its owner is enabled for geyser indexing.
  # Note that this does not check whether Geyser ingest is offline. Included
  # in the response is information which we can use during ingestion operations
  # to report on why a repository was rejected.
  def eligible_for_geyser_ingest_verbose
    T.bind(self, Repository)
    @eligible_for_geyser_ingest_verbose ||= if !code_is_searchable?
      { determination: false, reason: "code is not searchable" }
    elsif geyser_denylisted?
      { determination: false, reason: "repository in denylist" }
    elsif GitHub.use_elastomer_code_search?
      { determination: false, reason: "geyser not available in this env" }
    else
      { determination: true, reason: nil }
    end
  end

  # Return the boolean determination from `eligible_for_geyser_ingest_verbose`
  def eligible_for_geyser_ingest?
    eligible_for_geyser_ingest_verbose[:determination]
  end

  # Whether the current repository or its owner is enabled for geyser indexing.
  # Skips filtering on conditions that would short circuit based on disabled status
  def geyser_indexing_mutable_access_enabled?
    T.bind(self, Repository)
    # handle subset of repo_is_searchable? conditions
    return if network.nil? || T.unsafe(network).broken? || !routed?

    # handle subset of code_is_searchable? conditions
    return if empty? || (fork? && !popular_fork?)

    return false if geyser_denylisted?

    true
  end

  # Public: Check if slash commands are enabled for repo.
  #
  # Returns Boolean
  def slash_commands_enabled?
    return @slash_commands_enabled if defined?(@slash_commands_enabled)
    @slash_commands_enabled = GitHub.flipper[:slash_commands].enabled?(self)
  end

  # Public: Check if structure issue comment templates are enabled for repo.
  #
  # Returns Boolean
  def structured_issue_comment_templates_enabled?
    return @structured_issue_comment_templates_enabled if defined?(@structured_issue_comment_templates_enabled)
    @structured_issue_comment_templates_enabled = GitHub.flipper[:structured_issue_comment_templates].enabled?(self)
  end

  # Feature flags to include in the post_receive push event
  def post_receive_instrumentation_feature_flags
    T.bind(self, Repository)
    flags = []

    if eligible_for_geyser_ingest?
      flags << "geyser_ingest"
    end

    flags.concat(SecretScanning::Instrumentation::RepositoryServiceFlags.new(self).post_receive_service_flags)
    flags
  end

  # Language names to include in the post_receive push event
  def post_receive_language_names
    T.bind(self, Repository)
    language_percentages.map(&:first)
  end

  def pull_request_create_feature_flags
    T.bind(self, Repository)
    SecretScanning::Instrumentation::RepositoryServiceFlags.new(self).pull_request_scanning_service_flags
  end

  def alephd_language_indexing_enabled?
    T.bind(self, Repository)
    language_percentages.map(&:first).any? { |language| GitHub.flipper[GitHub::Aleph.convert_language_name(language)].enabled?(self) || GitHub.flipper[GitHub::Aleph.convert_darkship_language_name(language)].enabled?(self) }
  end

  # Is the current repository denylisted for geyser search indexing (will not be indexed)?
  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def geyser_denylisted?
    T.bind(self, Repository)
    @geyser_denylisted ||= begin
      GitHub.flipper[:geyser_denylist].enabled?(self) ||
        GitHub.flipper[:geyser_denylist].enabled?(self.owner)
    end
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  # True if the flag is set for this repo or the org/user it belongs to.
  def disqualify_pr_pushers_from_approving_feature_enabled?
    T.bind(self, Repository)
    (
      GitHub.flipper[:disqualify_pr_pushers_from_approving].enabled?(self) ||
      GitHub.flipper[:disqualify_pr_pushers_from_approving].enabled?(owner)
    )
  end

  def limit_environment_fetching?
    GitHub.flipper[:limit_environment_fetching].enabled?(self)
  end

  sig { params(feature_flag: Symbol).returns(Promise[T::Boolean]) }
  def async_scoped_feature_flag_enabled?(feature_flag)
    T.bind(self, Repository)
    if self.feature_enabled?(feature_flag)
      Promise.resolve(true)
    elsif owner.nil?
      Promise.resolve(false)
    elsif T.unsafe(owner).feature_enabled?(feature_flag)
      Promise.resolve(true)
    else
      T.unsafe(owner).async_business
        .then { |business| !business.nil? && business.feature_enabled?(feature_flag) }
    end
  end

  def show_branch_prot_violations_in_cli_feature_enabled?
    self.async_scoped_feature_flag_enabled?(:show_branch_prot_violations_in_cli).sync
  end

  # Overwrite the flipper_actor_name in GitHub::FlipperActor
  sig { override.returns(String) }
  def flipper_actor_name
    T.bind(self, Repository)
    name_with_display_owner
  end

  # Provide a custom implementation of the from_flipper_actor_name class method to override the one in GitHub::FlipperActor
  module ClassMethods
    extend T::Sig

    sig { params(name: String).returns(T.nilable(GitHub::FlipperActor)) }
    def from_flipper_actor_name(name)
      Repository.with_name_with_owner name
    end
  end

  mixes_in_class_methods(ClassMethods)

  # Overwrite the actor_tenant in GitHub::FlipperActor
  sig { returns(T.nilable(FeatureManagement::ActorTenant)) }
  def actor_tenant
    T.bind(self, Repository)
    if GitHub.multi_tenant_enterprise? && T.unsafe(owner).business
      tenant = T.unsafe(owner).business
      FeatureManagement::ActorTenant.new(tenant.name, tenant.id)
    else
      nil
    end
  end
end
