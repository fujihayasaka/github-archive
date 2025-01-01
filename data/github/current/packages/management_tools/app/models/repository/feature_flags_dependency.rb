# typed: true
# frozen_string_literal: true

# Allow us to set certain features based on if the repo is enabled for
# "preview_features" - this is most likely for private GitHub repos
#
# See app/models/user/feature_flag_methods.rb
# See also: http://martinfowler.com/bliki/FeatureToggle.html
module Repository::FeatureFlagsDependency
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
    @adaptive_card_parsing_enabled = FeatureFlag.vexi.enabled?(:adaptive_card_markdown_parsing, self, default: false)
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

  # Return true if this repository is eligible for publishing events to trigger Blackbird indexing.
  def eligible_for_blackbird_ingest?
    !GitHub.use_elastomer_code_search?
  end

  # Public: Check if slash commands are enabled for repo.
  #
  # Returns Boolean
  def slash_commands_enabled?
    return @slash_commands_enabled if defined?(@slash_commands_enabled)

    result = FeatureFlag.vexi.enabled(:slash_commands, self, default: false)
    raise result.error if result.error # preserve previous error handling behavior
    @slash_commands_enabled = result.value
  end

  # Public: Check if structure issue comment templates are enabled for repo.
  #
  # Returns Boolean
  def structured_issue_comment_templates_enabled?
    return @structured_issue_comment_templates_enabled if defined?(@structured_issue_comment_templates_enabled)

    result = FeatureFlag.vexi.enabled(:structured_issue_comment_templates, self, default: false)
    raise result.error if result.error # preserve previous error handling behavior
    @structured_issue_comment_templates_enabled = result.value
  end

  # Feature flags to include in the post_receive push event
  def post_receive_instrumentation_feature_flags
    T.bind(self, Repository)
    flags = []
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
    language_percentages.map(&:first).any? do |language|
      # Using `enabled_or_raise?` because the logic here gets unwieldy if we attempt to use `enabled`
      FeatureFlag.vexi.enabled_or_raise?(Search::Blackbird.convert_language_name(language), self) ||  # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      FeatureFlag.vexi.enabled_or_raise?(Search::Blackbird.convert_darkship_language_name(language), self) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    end
  end

  # True if the flag is set for this repo or the org/user it belongs to.
  def disqualify_pr_pushers_from_approving_feature_enabled?
    T.bind(self, Repository)
    result = FeatureFlag.vexi.enabled(:disqualify_pr_pushers_from_approving, self, owner, default: false)
    raise result.error if result.error # preserve previous error handling behavior
    result.value
  end

  def limit_environment_fetching?
    result = FeatureFlag.vexi.enabled(:limit_environment_fetching, self, default: false)
    raise result.error if result.error # preserve previous error handling behavior
    result.value
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

  # Overwrite the feature_flag_actor_name in GitHub::VexiActor
  sig { override.returns(String) }
  def feature_flag_actor_name
    T.bind(self, Repository)
    name_with_display_owner
  end

  # Provide a custom implementation of the from_feature_flag_actor_name class method to override the one in GitHub::VexiActor
  module ClassMethods
    sig { params(name: String).returns(T.nilable(GitHub::VexiActor)) }
    def from_feature_flag_actor_name(name)
      Repository.with_name_with_owner name
    end
  end

  mixes_in_class_methods(ClassMethods)

  # Overwrite the actor_tenant in GitHub::VexiActor
  sig { override.returns(T.nilable(FeatureManagement::ActorTenant)) }
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
