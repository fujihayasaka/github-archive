# typed: strict
# frozen_string_literal: true

# Listen for property changes that could affect setting values that need to trigger hooks
GitHub.subscribe("repo.update_custom_property_values") do |_name, _start, _ending, _transaction_id, payload|
  next unless FeatureFlag.vexi.enabled?(:settings_sdk_listeners, default: false)

  user = User.find_by(id: GitHub.context[:actor_id]) if GitHub.context[:actor_id]

  repo_id = payload[:repo_id]
  repository = Repository.find_by(id: repo_id)
  next unless repository

  old_values = payload[:old_values] || {}
  attribute = SettingsCoreV2::Conditions::RepositoryCustomPropertyMatcher::ATTRIBUTE

  attributes = old_values.map do |prop_name, value|
    SettingsCoreV2::AttributeOverride.new(
      resource: repository,
      attribute: "#{attribute}[#{prop_name}]",
      override: value,
    )
  end

  SettingsCoreV2::DomainRegistry.on_resource_update(
    repository,
    attributes,
    user,
  )
end

# Listen for new repositories, which may be children of organizations with settings that need to be applied on creation
GitHub.subscribe "repo.create" do |_name, _start, _ending, _transaction_id, payload|
  next unless FeatureFlag.vexi.enabled?(:settings_sdk_listeners, default: false)

  repo_id, actor_id = payload.values_at(:repo_id, :actor_id)
  repository = Repository.find_by(id: repo_id)
  next unless repository

  user = User.find_by(id: actor_id) if actor_id

  SettingsCoreV2::DomainRegistry.on_resource_create(
    repository,
    user,
  )
end
