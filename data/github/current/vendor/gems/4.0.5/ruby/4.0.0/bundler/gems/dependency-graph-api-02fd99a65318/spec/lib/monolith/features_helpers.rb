require_relative "../../../lib/monolith/features"

# Use this in an include inside a test block or else "double" won't be resolved.
module Monolith::FeaturesHelpers
  # Just feature name?: Completely enable it
  # Feature name + enabled_globally = false? Disable it everywhere
  # Feature name + enabled_owner / repo? Apply the given value to the feature broadly.
  # Feature name + a specific repository / owner id? Use the value of enabled_repository or enabled_owner, defaulting to true for enablement, and don't apply any wildcards.
  # Currently, this method can't be used multiple times subsequently in a row. You could fix that if you wanted.
  def mock_feature_check(feature_name, features_double: nil, github_repository_id: nil, github_owner_id: nil, enabled_repository: nil, enabled_owner: nil, enabled_globally: nil)
    mock_features = features_double.nil? ? double(Monolith::Features) : features_double
    allow(Monolith::Features).to receive(:new).and_return(mock_features)
    allow(mock_features).to receive(:feature_enabled?).and_return(false) # default all flags to false
    allow(mock_features).to receive(:feature_enabled?).with(feature: feature_name).and_return(enabled_globally == false ? false : true)
    allow(mock_features).to receive(:feature_enabled_for_repo?).and_return(false)
    allow(mock_features).to receive(:feature_enabled_for_repo_owner?).and_return(false)
    set_a_specific_id_value = false
    if github_repository_id.present?
      enabled_repository = enabled_repository.nil? ? true : enabled_repository
      allow(mock_features).to receive(:feature_enabled_for_repo?).with(github_repository_id: github_repository_id, feature: feature_name).and_return(enabled_repository)
      set_a_specific_id_value = true
    end
    if github_owner_id.present?
      enabled_owner = enabled_owner.nil? ? true : enabled_owner
      allow(mock_features).to receive(:feature_enabled_for_repo_owner?).with(github_repository_id: github_repository_id, feature: feature_name).and_return(enabled_owner)
      set_a_specific_id_value = true
    end
    # return here because a per ID value is very specific and we don't expect it to be combined with wildcards
    return if set_a_specific_id_value

    if enabled_repository.nil? && enabled_owner.nil? && feature_name.present?
      allow(mock_features).to receive(:feature_enabled_for_repo?).with(feature: feature_name, github_repository_id: anything).and_return(true)
      allow(mock_features).to receive(:feature_enabled_for_repo_owner?).with(feature: feature_name, github_owner_id: anything).and_return(true)
    else
      if !enabled_repository.nil? && feature_name.present?
        allow(mock_features).to receive(:feature_enabled_for_repo?).with(feature: feature_name, github_repository_id: anything).and_return(enabled_repository)
      end
      if !enabled_owner.nil? && feature_name.present?
        allow(mock_features).to receive(:feature_enabled_for_repo_owner?).with(feature: feature_name, github_owner_id: anything).and_return(enabled_owner)
      end
    end

    return mock_features
  end
end
