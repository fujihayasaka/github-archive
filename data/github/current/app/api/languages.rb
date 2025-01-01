# typed: true
# frozen_string_literal: true

class Api::Languages < Api::App
  get "/languages", operation_id: :unreleased do
    @route_owner = Platform::NoOwnerBecause::UNAUDITED
    control_access :apps_audited, resource: Platform::PublicResource.new, allow_integrations: true, allow_user_via_granular_actor: true # rubocop:disable GitHub/PublicResource

    languages = Linguist::Language.all.map do |l|
      {
        name: l.name,
        aliases: l.aliases,
      }
    end
    deliver_raw languages
  end
end
