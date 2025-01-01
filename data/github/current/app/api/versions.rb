# typed: true
# frozen_string_literal: true

class Api::Versions < Api::App
  # Returns a list of versions sorted from newest to oldest, excluding next.
  # To be re-iterated on as versions become more defined.
  get "/versions", operation_id: "meta/get-all-versions" do
    control_access :public_site_information, resource: Platform::PublicResource.new, allow_integrations: true, allow_user_via_granular_actor: true # rubocop:disable GitHub/PublicResource

    versions = Api::Versioning.sort_versions(GitHub.api_versions)
    versions.pop if versions.last == Api::Versioning::NEXT_VERSION
    versions.reverse!

    deliver_raw versions
  end
end
