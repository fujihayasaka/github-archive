# typed: false
# frozen_string_literal: true

module Stratocaster
  class Attributes::Push < Attributes
    EVENT_TYPE = "PushEvent".freeze

    # Initializes the attributes for this event.
    #
    # push_id   - The Integer ID of the Push record.
    # repo_id   - The Integer ID of the Repository the Push affected.
    # pusher_id - The Integer ID of the User that made the Push.
    # ref       - The String branch name the Push was applied to.
    # head      - The String HEAD of the repo before the Push.
    # shas      - The Array of Array tuples for each commit.  Each tuple has:
    #             id      - String Commit SHA
    #             email   - String Commit author email
    #             message - String Commit message.
    #             name    - Sring Commit author name.
    # shas_size - The Integer number of shas in the push.  If not given, the
    #             shas Array will be counted.
    #
    # Returns nothing.
    def from(push_id, repo_id, pusher_id)
      return unless @actor ||= User.find_by_id(pusher_id)
      return unless @repo ||= Repository.find_by_id(repo_id)
      return unless @push = Repositories.domain.pushes.by_id_and_repo_id(repository_id: repo_id, id: push_id)


      @push_id = @push.id
      @ref = @push.ref
      @head = @push.after
      # Getting total_commits_count first will also cache @commits, saving an extra rpc call in commits_summary
      @shas_size = @push.total_commits_count
      @shas = @push.commits_summary
      @distinct_shas_size = @push.distinct_commits_pushed.size
      @before = @push.before
    end

    # Converts a saved Event into the args necessary to get the other
    # attributes for this event type.
    #
    # event - A saved Stratocaster::Event instance.
    #
    # Returns nothing
    def from_event(event)
      @repo = event.repo_record if event.repo_record.is_a?(Repository)
      @actor = event.sender_record if event.sender_record.is_a?(User)
      from(event.push_id, event.repo_record&.id, event.sender_record&.id)
    end

    # Builds the Stratocaster::Event attribute hash.
    #
    # Returns a Hash of attributes for Stratocaster::Event#dispatch.
    def to_hash
      return {} unless @actor && @repo && @push
      {
        event_type: EVENT_TYPE,
        repo: @repo,
        sender: @actor,
        url: url,
        payload: payload,
      }
    end

    # Builds the list of targets for an event.
    #
    # timeline_type - an optional String for the timeline that will be shown
    #
    # Returns an Array of User IDs.
    def targets(timeline_type = nil)
      targets_for @repo
    end

    # Builds the event's payload.
    #
    # Returns a Hash.
    def payload
      {
        repository_id: @repo.id,
        push_id: @push_id,
        size: @shas_size,
        distinct_size: @distinct_shas_size,
        ref: @ref,
        head: @head,
        before: @before,
        commits: @shas.map do |(id, email, message, name, is_distinct)|
          {
            sha: id,
            author: { email: email, name: name },
            message: message,
            distinct: is_distinct,
            url: "#{GitHub.api_url}/repos/#{@repo.name_with_owner}/commits/#{id}",
          }
        end,
        legacy: {
            push_id: @push_id,
            shas: @shas,
            size: @shas_size,
            ref: @ref,
            head: @head,
          },
      }
    end

    # Builds the event's unique URL. This will be without the host url
    # because staff/enterprise environments can have different domains, and the
    # event data will be cached.
    #
    # Returns a String URL.
    def url
      @push.permalink(include_host: false)
    end
  end
end
