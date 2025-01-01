# typed: true
# frozen_string_literal: true

class Hook::Event::RepositoryAdvisoryEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS

  description "Repository advisory published or reported."

  event_attr :action, :repository_advisory_id, required: true
  event_attr :installation, :enterprise

  def repository_advisory
    @repository_advisory ||= RepositoryAdvisory.find(repository_advisory_id)
  end

  def target_repository
    @repository ||= repository_advisory.repository
  end

  def target_organization
    owner ||= target_repository&.owner
    owner&.organization? ? owner : nil
  end

  def actor
    case action.to_sym
    when :published
      repository_advisory.publisher
    when :reported
      repository_advisory.author
    end
  end

  def deliverable?
    case action.to_sym
    when :published
      repository_advisory&.published?
    when :reported
      repository_advisory.present?
    end
  end
end
