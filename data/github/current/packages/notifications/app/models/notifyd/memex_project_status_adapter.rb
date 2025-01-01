# typed: true
# frozen_string_literal: true

module Notifyd
  class MemexProjectStatusAdapter < SubjectAdapter
    Layouts = Notifyd::Proto::Layouts::Email

    include Notifyd::Email
    include UrlHelpers
    include GitHub::Memoizer

    THREAD_TYPE = "memex_project".freeze

    def matches?
      !memex_project.deleted?
    end

    def notify_feature_flag
      GitHub.flipper[:notifyd_memex_project_status_notify]
    end

    def notification_id
      subject.permalink(include_host: false)
    end

    # MemexProjects do not belong to a repository
    def repository_id
      nil
    end

    def authzd_attributes
      memex_project.permissions_wrapper.serialized_subject_attributes
    end

    memoize def actor
      case operation
      when Operations::MemexProjectStatusOperation::Update
        User.find_by(id: context[:actor_id])
      when Operations::MemexProjectStatusOperation::Create
        subject.creator
      else
        subject.creator
      end
    end

    def saml_enforcement
      return unless memex_project.org_owned?

      { organization_id: memex_project.owner_id }
    end

    # There is no support for MemexProjectStatus on mobile at this time, to be implemented later.
    def mobile_layout
      nil
    end

    def email_layout
      author = Email::AuthorUser.new(user: subject.creator)

      Email::MemexProjectStatusRenderer.new(
        memex_project_status: subject,
        author: author,
        actor: actor,
      ).render
    end

    memoize def related_topics
      organization_related_topic = if memex_project.org_owned?
        { type: "organization", value: memex_project.owner_id.to_s }
      end

      [
        { type: THREAD_TYPE, value: subject.memex_project_id.to_s },
        organization_related_topic,
      ].compact
    end

    def explicit_recipients
      case operation
      when Notifyd::Operations::MemexProjectStatusOperation::Create,
        Notifyd::Operations::MemexProjectStatusOperation::Update

        Notifyd::RecipientsHelper.new(
          subject,
          operation.serialize,
          context[:previous_body],
          context[:current_body],
        ).explicit_recipients
      else
        []
      end
    end

    def attributes
      [
        { name: "thread_participant_activity", value: "true" },
        { name: "thread_type", value: THREAD_TYPE },
        # Uncomment when we allow users to watch MemexProjects, at the moment you have to manually subscribe to the
        # thread (MemexProject).
        # { name: "watch_activity", value: "true" },
      ]
    end

    # This value will be used in anti-abuse checks that will determine whether a user is allowed to receive a notification
    # with this related subject.
    def owner_id
      memex_project.owner_id
    end

    def owner_type
      memex_project.org_owned? ? :organization : :user
    end

    def trigger
      context[:operation]
    end

    def feature_switches
      {
        notify_actor: false,
        notify_subscribers: true
      }
    end

    private

    def operation
      @operation ||= Operations::MemexProjectStatusOperation.try_deserialize_or_unknown(trigger)
    end

    def memex_project
      subject.memex_project
    end
  end
end
