# typed: true
# frozen_string_literal: true

module Notifyd
  # To implement a new notification type, it is necessary to add a specific adapter for the notification type. e.g. IssueAdapter
  # The adapters should provide the necessary data to send a notifyd message.
  #
  # SubjectAdapter is the base class for these adapters and its first purpose is to verify all specific adapters are well defined.
  # If any adapter does not have a mandatory method, an error will be raised.
  # For non-mandatory methods, a default value is set, like `.matches?` does.
  # It includes a registry of all the adapters, used to fetch a specific adapter.
  #
  # subject - The resource related to the notification. E.g. if someone was mentioned in an issue comment,
  #           the subject would be the IssueComment instance containing the mention.
  # context - key-value hash of attributes. The content of the context is flexible and depends on the needs of the integrators.
  #           It could be used in the adapters for different purposes: to get explicit recipients, to define the layout,...
  #           E.g. {
  #                  operation: 'create',
  #                  actor_login: 'actor',
  #                  previous_body: 'this is the body'
  #                }
  #
  # Both are provided when publishing a notification with `NotifyPublisher`.
  # The publisher is called asynchronously, so we need to make sure all dependencies exist, using the `matches?` method for example.
  #
  class SubjectAdapter
    class Error < StandardError; end
    class MissingNotificationIdError < Error; end
    class MissingFeatureFlagError < Error; end
    class MissingSubjectAdapterError < Error; end
    class UnknownOwnerTypeError < Error; end

    # FeatureEnabled is used to replace real feature flags that have been removed
    # because they have been already enabled for a long time
    class FeatureEnabled
      def enabled?(*)
        true
      end

      def ==(other)
        other.kind_of?(self.class)
      end
    end

    POSSIBLE_OWNER_TYPES = {
      user: :USER,
      organization: :ORGANIZATION
    }

    # Default map between possible reasons and their description to show in plain English
    REASONS_TO_WORDS = {
      mention: "you were mentioned",
      comment: "you commented on the thread",
      author: "you authored the thread",
      manual: "you are subscribed to this thread",
      team_mention: "you are on a team that was mentioned",
      assign: "you were assigned",
      review_requested: "your review was requested",
      state_change: "you modified the open/close state",
      security_alert: "you have alerting access",
      ci_activity: "this workflow ran on your branch",
      security_advisory_credit: "you were given credit for contributing to a Security Advisory",
      approval_requested: "your approval was requested for deployment",
      member_feature_requested: "you have pending member feature requests",
    }

    attr_reader :subject, :context

    def initialize(subject, context = {})
      @subject = subject
      @context = context
    end

    def self.adapter_for_subject(subject, context = {})
      registry = {
        "Issue" => Notifyd::IssueAdapter,
        "IssueComment" => Notifyd::IssueCommentAdapter,
        "IssueEvent" => Notifyd::IssueEventAdapter,
        "PullRequest" => Notifyd::PullRequestAdapter,
        "PullRequestReview" => Notifyd::PullRequestReviewAdapter,
        "Discussion" => Notifyd::DiscussionAdapter,
        "DiscussionComment" => Notifyd::DiscussionCommentAdapter,
        "CheckSuite" => Notifyd::CheckSuiteAdapter,
        "GateRequest" => Notifyd::GateRequestAdapter,
        "GistComment" => Notifyd::GistCommentAdapter,
        "MemberFeatureRequest::Notification" => Notifyd::MemberFeatureRequestAdapter,
        "MemexProjectStatus" => Notifyd::MemexProjectStatusAdapter,
        "Release" => Notifyd::ReleaseAdapter,
        "SecurityCampaigns::SecurityCampaignUser" => Notifyd::SecurityCampaignUserAdapter,
      }

      klass = registry[subject.class.name]
      # This is a safeguard against the case when the adapater doesn't exist for the subject.
      # We cannot return nil here as it would be interpreted by the caller that the adapter exists
      # but the call to `matches?` fails. We want to explicitly raise an error here because this is
      # unexpected behavior and should result in a Failbot report unless explicitly handled.
      raise MissingSubjectAdapterError.new("No adapter exists for subject of type #{subject.class.name}") unless klass.present?

      instance = klass.new(subject, context)
      instance if instance.matches?
    end

    def self.notification_id_from_subject(subject)
      adapter = adapter_for_subject(subject)
      return unless adapter

      notification_id = adapter.notification_id
      raise MissingNotificationIdError.new("notification_id must return something") unless notification_id

      notification_id
    rescue MissingSubjectAdapterError
      nil
    end

    def self.notify_feature_flag_from_subject(subject)
      adapter = adapter_for_subject(subject)
      return unless adapter

      feature_flag = adapter.notify_feature_flag
      raise MissingFeatureFlagError.new("notify_feature_flag must return something") unless feature_flag

      feature_flag
    rescue MissingSubjectAdapterError
      nil
    end

    def notify_feature_flag
      raise MissingFeatureFlagError.new("Adapters must define the notify_feature_flag method")
    end

    def notification_id
      raise MissingNotificationIdError.new("Adapters must define the notification_id method")
    end

    def matches?
      true
    end

    # Returns the id of the repository associated to the notification's subject.
    # This will be used to skip notifications for repositories that are ignored by the recipient.
    def repository_id
      raise NotImplementedError.new("Adapters must define the repository_id method")
    end

    # Returns a key-value hash of attributes that will be forwarded to authzd to evaluate
    # the policy for the `receive_notification` action and the notification's subject.
    # Notifyd will use this auth check to decide whether a recipient is allowed to receive a notification
    # for the given subject or not.
    # The authzd attributes of a model are often defined in a permissions wrapper class
    # and can be accessed via model_instance.permissions_wrapper.serialized_subject_attributes
    def authzd_attributes
      raise NotImplementedError.new("Adapters must define the authzd_attributes method")
    end

    # Returns a hash containing data to enforce a valid SAML session.
    # The hash should either provide the id of the organization owning the notification's subject:
    #   { organization_id: owning_organization.id } or { skip_enforcement: true } if the subject
    # is not owned by an organization and thus SAML shouldn't be enforced. SAML enforcement needs
    # to be explicitly skipped. Providing `nil` for `organization_id` will throw an error.
    def saml_enforcement
      raise NotImplementedError.new("Adapters must define the saml_enforcement method")
    end

    # Returns a protobuf instance of a notification layout that should be used to render a mobile push notification.
    # The protobufs for mobile layouts are generated in https://github.com/github/notifyd/blob/main/ruby/lib/notifyd/proto/layouts/mobile/layouts_pb.rb
    def mobile_layout
      raise NotImplementedError.new("Adapters must define the mobile_layout method")
    end

    # Returns protobuf instance of a email layout that should be used to render an email message.
    # The protobufs for email layouts are generated in https://github.com/github/notifyd/blob/main/ruby/lib/notifyd/proto/layouts/email/layouts_pb.rb
    def email_layout
      raise NotImplementedError.new("Adapters must define the email_layout method")
    end

    # Returns array of hashes, each of them contains topic for notification
    def related_topics
      raise NotImplementedError.new("Adapters must define the related_topics method")
    end

    # Returns an array of hashes, each of them cointains attribute used for subscription and settings matching
    def attributes
      raise NotImplementedError.new("Adapters must define the attributes method")
    end

    # Returns a string denoting the trigger reason for a notification
    def trigger
      raise NotImplementedError.new("Adapters must define the trigger method")
    end

    # Array of hashes providing a reason string and user objects.
    # Notifyd will use this array of hashes to determine recipients of the notification. Example:
    # Assuming the comment "Hello @user and @other_user, you should join @github/team",
    # we'd generate the following array to tell Notifyd which users to notify:
    #  [
    #     { reason: "mention", users: [user] },
    #     { reason: "mention", users: [other_user] },
    #     { reason: "team_mention", users: [member1, member2, member3] }
    #  ]
    def explicit_recipients
      raise NotImplementedError.new("Adapters must define the explicit_recipients method")
    end

    # User id of subject parent owner.
    # This value will be used in anti-abuse checks that will determine whether a user is allowed to receive a notification
    # with this related subject.
    #
    # As part of those checks we ensure that recipients won't get notification if
    # subject is owned by a user that was blocked by the recipient.
    #
    # We assume here that owner is related to User model (User/Organization/Bot).
    #
    # Common examples of such Id could be:
    #  - Subject: PullRequest, Issue -> id of the user/organization owning the repository, where Issue/PR was created
    #  - Subject: Gist -> id of the user/organization that owns Gist
    def owner_id
      raise NotImplementedError.new("Adapters must define the owner_id method")
    end

    # Returns true if subject contains non null body html
    def subject_body_html?
      @subject.respond_to?(:body_html) && @subject.body_html.present?
    end

    # Returns true if subject contains non null body_html_for_email
    def subject_body_email_html?
      @subject.respond_to?(:body_html_for_email) && @subject.body_html_for_email.present?
    end

    # Returns subject body in html format if it's present, otherwise we will fallback to plain text
    def subject_body
      if subject_body_email_html?
        @subject.body_html_for_email.to_str
      elsif subject_body_html?
        @subject.body_html.to_str
      else
        @subject.body
      end
    end

    # Returns either :user or :organization depending on the type of the owner
    def owner_type
      raise NotImplementedError.new("Adapters must define the owner_type method")
    end

    # Returns feature switches that should be enabled/disabled for given subject
    def feature_switches
      {}
    end

    def email_reasons_to_words
      REASONS_TO_WORDS
    end

    def reason_groups
      [
        { name: "notify_muted", reasons: %w[mention team_mention] },
        { name: "participant", reasons: %w[author comment assign state_change mention team_mention manual] },
      ]
    end

    # Returns the proper value for the protocolbuffer enum to use in a hydro
    # message
    def self.owner_type_enum(owner_type)
      unless POSSIBLE_OWNER_TYPES.keys.include?(owner_type)
        raise UnknownOwnerTypeError.new("owner type must be one of #{POSSIBLE_OWNER_TYPES.values.join(",").downcase}")
      end
      POSSIBLE_OWNER_TYPES[owner_type]
    end
  end
end
