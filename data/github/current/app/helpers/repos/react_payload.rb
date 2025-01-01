# typed: true
# frozen_string_literal: true

module Repos::ReactPayload
  extend Repos::GitHubEnterpriseHelper
  extend Scientist
  def self.current_repository_payload(repo, current_user_can_push:)
    {
      id: repo.id,
      defaultBranch: repo.default_branch,
      name: repo.name,
      ownerLogin: repo.owner_display_login,
      currentUserCanPush: current_user_can_push,
      isFork: repo.fork?,
      isEmpty: repo.empty?,
      createdAt: repo.created_at,
      ownerAvatar: repo.owner.primary_avatar_url || User::AvatarList.default_image_url("gravatar-user-420"),
      public: repo.public?,
      private: repo.private?,
      isOrgOwned: repo.owner.organization?
    }
  end

  def self.current_repository_nwo_payload(repo)
    {
      name: repo.name,
      ownerLogin: repo.owner_display_login,
    }
  end

  def self.app_payload(find_file_worker_path, find_in_file_worker_path, github_dev_enabled)
    {
      helpUrl: GitHub.help_url,
      findFileWorkerPath: find_file_worker_path,
      findInFileWorkerPath: find_in_file_worker_path,
      githubDevUrl: github_dev_enabled ? GitHub.codespaces_serverless_url : nil
    }
  end

  def self.code_nav_payload(location_with_path, highlighted_text, repo)
    payload = {
      first_line: location_with_path.first_line,
      ident: {
        start: {
          line: location_with_path.ident.start.line,
          character: location_with_path.ident.start.character
        },
        end: {
          line: location_with_path.ident.end.line,
          character: location_with_path.ident.end.character
        }
      },
      path: location_with_path.path,
      kind: location_with_path.kind,
      symbol_kind: location_with_path.symbol_kind,
      uri: location_with_path.uri,
      local: location_with_path.local,
      commit_oid: location_with_path.pkg.commit_oid,
      highlighted_text: highlighted_text,
      # We don't really care if the user can push
      repo: current_repository_payload(repo, current_user_can_push: false),
      leading_whitespace: location_with_path.leading_whitespace,
    }

    if location_with_path.respond_to?(:extent)
      payload[:extent] = {
        start: {
          line: location_with_path.extent.start.line,
          character: location_with_path.extent.start.character
        },
        end: {
          line: location_with_path.extent.end.line,
          character: location_with_path.extent.end.character
        }
      }
    end

    payload
  end

  def self.current_user_payload(user)
    return nil unless user
    {
      id: user.id,
      login: user.display_login,
      userEmail: user.email,
    }
  end

  def self.current_user_payload_for_diff(user)
    return nil unless user
    {
      id: user.id,
      login: user.display_login,
      userEmail: user.email,
      avatarURL: user.primary_avatar_url,
      tabSize: user.settings.get(:tab_size),
    }
  end

  # Converts the keys of the given hash from Ruby style `snake_case` to JavaScript style `camelCase`.
  # This method is not as fast as you might hope, taking on the order of milliseconds, so we should avoid using it
  # as much as possible.
  def self.camelize_keys(hash)
    hash.deep_transform_keys { |key| key.is_a?(Symbol) ? key.to_s.camelize(:lower) : key }
  end

  # Use this method when migrating away from camelize_keys to check that any nested payloads aren't missed
  # after deploying.
  def self.camelize_keys_science(hash)
    science "dont_camelize_keys" do |e|
      e.use { camelize_keys(hash) }
      e.try { hash }
      e.clean do |value|
        # we only care about the key names, so we strip out all the values
        cleaned = value.deep_transform_values { |v| v.is_a?(Hash) ? v : nil }
        cleaned.deep_transform_keys! { |k| k.to_s }
        cleaned
      end
      e.compare do |control, candidate|
        # sometimes keys are strings, sometimes they're symbols, we need to normalize for the comparison to work
        control.deep_transform_keys { |k| k.to_s } == candidate.deep_transform_keys { |k| k.to_s }
      end
    end
  end

  def self.repo_create_payload(owner_items, cap_filter, current_user)
    {
      ownerItems: owner_items,
      restrictCreateRepositoriesInPersonalNamespace: restrict_create_repositories_in_personal_namespace?(current_user),
      helpUrl: GitHub.help_url,
      docsUrls: {
        licensePicker: DocsUrlConfig.url_for("repositories/licensing-a-repository"),
      }
    }
  end

  def self.code_view_feature_flags
    [
      :code_nav_ui_events,
      :react_blob_overlay,
      :accessible_code_button
    ].freeze
  end
end
