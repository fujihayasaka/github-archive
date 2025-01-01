# typed: false
# frozen_string_literal: true

module Api::Serializer::EventsDependency
  def stratocaster_event_hash(event, options = {})
    tags = ["event_type:#{event.event_type}"]
    GitHub.dogstats.distribution_time("stratocaster.api_event_hash", tags:) do
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
      hash[:actor][:avatar_url] = event_avatar_url(event.sender["id"])

      if repo = hash[:repo]
        repo[:name] = "#{event.user['login']}/#{repo.delete('name')}"
        repo[:url]  = url("/repos/#{repo[:name]}")
        repo.delete("source_id")
      end

      if !event.org.blank?
        org = event.org
        org[:url] = url("/orgs/#{org['login']}")
        org[:avatar_url] = event_avatar_url(org["id"], true)
        hash[:org] = org
      end

      hash
    end
  end

  def conduit_event_hash(event, options = {})
    tags = ["event_type:#{event.class.name.demodulize.underscore}"]
    GitHub.dogstats.distribution_time("conduit.api_event_hash", tags:) do
      actor = event.actor
      repo = event.repository

      # Only massage payload for PublishedWiki events
      payload = event.is_a?(Conduit::FeedItem::PublishedWiki) ? massage_conduit_payload_urls(event) : event.payload

      hash = {
        id: event.event_id.to_s,
        type: event.api_type,
        actor: conduit_actor_hash(actor),
        repo: repo_hash(repo),
        payload: payload,
        public: public?(event),
        created_at: time(event.created_at),
      }

      if repo&.owner&.organization?
        org = conduit_actor_hash(repo.owner)
        org.delete(:display_login)
        org[:url] = url("/orgs/#{repo.owner.display_login}")
        org[:avatar_url] = event_avatar_url(repo.owner.id, true)
        hash[:org] = org
      end

      hash
    end
  end

  def conduit_actor_hash(actor)
    {
      id: actor.id,
      login: actor.display_login,
      display_login: get_display_login(actor),
      gravatar_id: "",
      url: url("/users/#{actor.display_login}"),
      avatar_url: event_avatar_url(actor.id)
    }
  end

  def repo_hash(repo, _options = nil)
    return {} unless repo

    {
      id: repo.id,
      name: "#{repo.owner_display_login}/#{repo.name}",
      url: url("/repos/#{repo.owner_display_login}/#{repo.name}")
    }
  end

  def public?(event)
    event&.repository&.public? || event&.api_type == "SponsorshipEvent"
  end

  def get_display_login(actor)
    actor.is_a?(Bot) ? actor.slug : actor.display_login
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

  def massage_conduit_payload_urls(event)
    payload = event.payload.dup
    case event
    when Conduit::FeedItem::PublishedWiki
      payload.fetch(:pages, []).each do |page_payload|
        next unless path = page_payload[:html_url]
        unless path =~ /\A#{URI::regexp}\z/
          page_payload[:html_url] = html_url(path)
        end
      end
    end
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
