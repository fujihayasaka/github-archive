# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("repository_search_shortcut.create") do |payload|
    repository = Repository.find_by(id: payload[:repository_id])
    next unless repository

    actor = User.find_by(id: payload[:actor_id])
    next unless PinnedViewsFeature.hydro_enabled?(repository, actor: actor)

    message = {
      action: :ACTION_CREATE,
      actor: serializer.user(actor),
      repository: serializer.repository(repository),
      shortcut_id: payload[:shortcut_id],
      creator_id: payload[:creator_id],
      search_type: repository_search_shortcut_search_type(payload[:search_type]),
      pinned: payload[:pinned],
      has_description: payload[:has_description],
      source: repository_search_shortcut_source(payload[:source]),
    }

    publish(message, schema: "github.issues.v0.RepositorySearchShortcut")
  end

  subscribe("repository_search_shortcut.update") do |payload|
    repository = Repository.find_by(id: payload[:repository_id])
    next unless repository

    actor = User.find_by(id: payload[:actor_id])
    next unless PinnedViewsFeature.hydro_enabled?(repository, actor: actor)

    message = {
      action: :ACTION_UPDATE,
      actor: serializer.user(actor),
      repository: serializer.repository(repository),
      shortcut_id: payload[:shortcut_id],
      creator_id: payload[:creator_id],
      search_type: repository_search_shortcut_search_type(payload[:search_type]),
      pinned: payload[:pinned],
      has_description: payload[:has_description],
    }

    publish(message, schema: "github.issues.v0.RepositorySearchShortcut")
  end

  subscribe("repository_search_shortcut.destroy") do |payload|
    repository = Repository.find_by(id: payload[:repository_id])
    next unless repository

    actor = User.find_by(id: payload[:actor_id])
    next unless PinnedViewsFeature.hydro_enabled?(repository, actor: actor)

    message = {
      action: :ACTION_DESTROY,
      actor: serializer.user(actor),
      repository: serializer.repository(repository),
      shortcut_id: payload[:shortcut_id],
      creator_id: payload[:creator_id],
      search_type: repository_search_shortcut_search_type(payload[:search_type]),
      pinned: payload[:pinned],
      has_description: payload[:has_description],
    }

    publish(message, schema: "github.issues.v0.RepositorySearchShortcut")
  end

  def repository_search_shortcut_search_type(value)
    return :SEARCH_TYPE_UNKNOWN unless RepositorySearchShortcut.search_types.key?(value.to_s)

    "SEARCH_TYPE_#{value.to_s.upcase}".to_sym
  end

  def repository_search_shortcut_source(value)
    case value.to_s
    when "new" then :SOURCE_NEW
    when "duplicate" then :SOURCE_DUPLICATE
    else :SOURCE_UNKNOWN
    end
  end
end
