# typed: true
# frozen_string_literal: true

class Issue::Adapter::RepositoryAdapter < Issue::Adapter::Base
  TYPES = [
    PlatformTypes::RepositoryNode
  ].freeze

  attr_reader :id
  attr_reader :name
  attr_reader :name_with_display_owner
  attr_reader :database_id
  attr_reader :owner
  attr_reader :owner_login
  attr_reader :viewer_can_see_commenter_full_name
  attr_reader :is_private

  attr_reader :tasklist_block_enabled
  attr_reader :convert_to_tasklist_block_enabled
  attr_reader :slash_commands_enabled
  attr_reader :resource_path
  attr_reader :checks_statuses_rollups_resource_path

  delegate :organization, :async_viewer_can_see_commenter_full_name?, :feature_flag_enabled_or_raise?, :feature_flag_enabled?, to: :@repository

  def initialize(context, repository:)
    super(context)

    viewer = context.viewer

    @repository = repository
    @name = repository.name

    @name_with_display_owner = repository.name_with_display_owner
    @database_id = repository.id
    @id = repository.global_relay_id
    @is_private = repository.private?

    @owner = repository.owner
    @owner_login = repository.owner_display_login

    @viewer_can_see_commenter_full_name = repository.viewer_can_see_commenter_full_name?(viewer)

    # all are flipper checks:
    @slash_commands_enabled = repository.slash_commands_enabled?
    @tasklist_block_enabled = repository.owner.feature_flag_enabled_or_raise?(:tasklist_block) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    @convert_to_tasklist_block_enabled = repository.owner.feature_flag_enabled_or_raise?(:convert_to_tasklist_block) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

    @resource_path = resource_path_for(repository.path_uri)
    @checks_statuses_rollups_resource_path = "/#{repository.owner_display_login}/#{repository.name}/commits/checks-statuses-rollups"
  end

  def default_branch_ref
    return @default_branch_ref if defined?(@default_branch_ref)
    @default_branch_ref = Issue::Adapter::GitReferenceAdapter.new(context, ref: @repository.default_branch_ref) unless @repository.default_branch_ref.nil?
  end

  def slash_commands_enabled?
    @slash_commands_enabled
  end

  def is_private?
    @is_private
  end

  alias_method :private?, :is_private?

  def is_archived?
    @repository.archived?
  end

  def has_issues_enabled?
    @repository.has_issues?
  end

  def copilot_swe_agent_enabled?(viewer)
    @repository.copilot_swe_agent_enabled?(viewer)
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
