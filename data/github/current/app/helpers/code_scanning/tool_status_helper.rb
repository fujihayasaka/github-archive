# typed: true
# frozen_string_literal: true

module CodeScanning::ToolStatusHelper
  include ActionView::Helpers::RenderingHelper
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::UrlHelper
  extend T::Sig

  CODEQL_EXTENSION_PACKAGE_ECOSYSTEM = "container"

  def format_external_repository(uses)
    nwo_path, _, revision = uses.rpartition("@")
    owner, name, path = nwo_path.split("/", 3)

    view_component = if owner.blank? || name.blank? || path.blank? || revision.blank?
      Primer::Beta::Text.new(tag: :span)
    else
      Primer::Beta::Link.new(href: UrlHelpers.blob_path(name: revision, repository: name, user_id: owner, path: path))
    end.with_content(uses)

    ApplicationController.render(view_component, formats: [:html], layout: false)
  end

  def format_language(language)
    # If the language starts with an uppercase letter, then it is already a display name, so return it
    if language.first.upcase == language.first
      return language
    end

    # aliases that are not known by linguist
    return "Python" if language == "py"
    return "C#" if language == "cs"
    # everything else
    Linguist::Language.find_by_alias(language).try(:name) || language.capitalize
  end

  sig { params(category: String).returns(String) }
  def format_category(category)
    if %r{\A\.github/workflows/([^:]+\.ya?ml):(?:[^/]+/)?(.*)\z} =~ category
      return $2 if $1.present? && $2.present?
    end

    category.delete_prefix("/").gsub("([/:])", "\1\u200B").presence || "Unnamed"
  end

  def name_with_version(name, version)
    return name if version.blank?
    "#{name} (#{version})"
  end

  def extension_with_link(tool_name, name, version)
    result = name
    if !GitHub.enterprise? || GitHub.registry_v2_enabled_for_enterprise?
      if tool_name == "CodeQL" && name.count("/") == 1
        pack_owner_name, pack_name = name.split("/")
        registry_client = PackageRegistry::Twirp.metadata_client
        # https://github.com/github/app-partitioning/issues/53
        current_user = T.unsafe(self).current_user
        begin
          package_metadata = registry_client.get_package_metadata(
            ecosystem: CODEQL_EXTENSION_PACKAGE_ECOSYSTEM,
            namespace: pack_owner_name,
            name: pack_name,
            actor: current_user,
            version_limit: 1,
          )
          if package_metadata.present?
            url_prefix = package_metadata.package.owner.is_a?(Organization) ? "orgs" : "users"
            result = link_to(name, Rails.application.routes.url_helpers.packages_two_view_path(url_prefix, pack_owner_name, CODEQL_EXTENSION_PACKAGE_ECOSYSTEM, pack_name))
          end
        rescue PackageRegistry::Twirp::PermissionDeniedError
          # If the user doesn't have access to the package we just don't link it
        rescue PackageRegistry::Twirp::BaseError => e
          # If the package registry is having issues we don't want to fail the whole page.
          Failbot.report(e)
        end
      end
    end
    result += " (#{version})" if version.present?
    result
  end
end
