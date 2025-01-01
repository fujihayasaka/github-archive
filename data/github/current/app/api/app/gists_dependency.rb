# typed: strict
# frozen_string_literal: true

module Api::App::GistsDependency
  extend T::Helpers

  requires_ancestor { Api::App::ErrorDependency }

  sig { params(gist: Gist).void }
  def deliver_disabled_gist_error!(gist)
    control_access :get_gist, resource: gist, allow_integrations: false, allow_user_via_granular_actor: true

    gist.disabled_access_reason # preload the association

    halt deliver(:disabled_gist_hash, gist, status: 403)
  end
end
