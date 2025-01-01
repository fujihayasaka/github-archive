# typed: false
# frozen_string_literal: true

module Api::Serializer::EventsDependency
  def stratocaster_event_hash(event, options = {})
    hash = {
      id: event.id.to_s,
      type: event.event_type,
      actor: event.sender,
      repo: event.repo,
      payload: event_payload(event),
      public: event.public?,
      created_at: time(event.created_at),
    }

    hash[:actor][:url] = url("/users/#{event.sender['login']}")
    hash[:actor][:avatar_url] = event_avatar_url(event.sender)

    if repo = hash[:repo]
      repo[:name] = "#{event.user['login']}/#{repo.delete('name')}"
      repo[:url]  = url("/repos/#{repo[:name]}")
      repo.delete("source_id")
    end

    if !event.org.blank?
      org = event.org
      org[:url] = url("/orgs/#{org['login']}")
      org[:avatar_url] = event_avatar_url(org, true)
      hash[:org] = org
    end

    hash
  end

  # Remove the repository attributes from a Stratocaster event payload to ensure
  # adherence to the V3 endpoint schema.
  #
  # event - a Stratocaster::Event
  #
  # Returns a payload Hash or nil
  def event_payload(event)
    payload = massage_payload_urls(event)
    payload.delete("repository")
    payload
  end

  # Prefix any html_urls which may be stored as relative paths
  # with the correct site URL.
  #
  # event - a Stratocaster::Event
  #
  # Returns a payload Hash or nil (even if no URLs are wrapped)
  def massage_payload_urls(event)
    payload = event.current_payload.dup

    case event.event_type
    when Stratocaster::Event::GOLLUM_EVENT
      payload.fetch("pages", []).each do |page_payload|
        next unless path = page_payload["html_url"]

        unless path =~ /\A#{URI::regexp}\z/
          page_payload["html_url"] = html_url(path)
        end
      end
    end

    payload
  end
end
