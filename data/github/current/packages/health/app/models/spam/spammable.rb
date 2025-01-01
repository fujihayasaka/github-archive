# typed: false
# frozen_string_literal: true

module Spam
  # Provides spam related scopes and methods to AR models
  # that are associated with a user who may or may not be
  # flagged as spammy.
  #
  # Used for things like PullRequest, IssueComment, etc.
  module Spammable
    include Spam::ContentUserIsSpammy
    extend ActiveSupport::Concern

    def self.add_class_including(klass)
      @tables_classes_including ||= {}
      @tables_classes_including[klass.table_name.to_sym] = klass
    end

    def self.tables_classes_including
      @tables_classes_including ||= {}
    end

    included do
      extend ClassMethods
      after_validation :set_user_hidden
      after_commit :instrument_user_hidden_change, on: [:create, :update], if: :user_hidden_previously_changed?
    end

    module ClassMethods
      # Setup the scopes and methods for the name of the user
      # association (the potential spammer) used in the model.
      #
      # user_association - a Symbol, the name of the user association
      #                    (:user, :owner, :author, etc)
      def setup_spammable(user_association)
        spammable_has_simple_user = begin
          user_association = user_association.to_s
          reflection = reflections[user_association]
          unless reflection
            raise RuntimeError, "You must call 'setup_spammable' after the '#{user_association}' association is loaded"
          end
          is_belongs_to   = reflection.macro == :belongs_to
          unknown_options = reflection.options.keys - [:class_name, :foreign_key, :dependent, :as, :touch, :required, :optional, :polymorphic]
          is_belongs_to && unknown_options.empty?
        end
        unless spammable_has_simple_user
          raise ArgumentError, "#{self}'s '#{user_association}' association is not a simple :belongs_to and cannot be used with spammable."
        end

        # Exclude records that are made by spammy users, unless the
        # viewer is staff or the spammer who created the record.
        #
        # Includes records that were created by users
        # who no longer exist (ghosts).
        #
        # If you are using `filter_spam_for` on Issues or PRs, you need to manually
        # also filter for `repositories.user_hidden: false` at the callsite in order
        # to filter out Issues or PRs belonging to spammy repos.
        #
        # viewer - The User we are rendering the records for.
        #          Usually should be current_user. Accomodates viewer
        #          being nil/false for anonymous users.
        # show_spam_to_staff - Override the assumption that staff should
        #                      see spam by setting this to `false`.
        #                      Defaults to `true`.
        scope :filter_spam_for, lambda { |viewer, show_spam_to_staff: true, foreign_key: nil, skip_user_filter_if_not_spammy: false|
          return if !GitHub.spamminess_check_enabled?

          # We don't filter anything for staff
          return if show_spam_to_staff && viewer.try(:site_admin?)

          # Without a viewer, we only show non-spammy records
          return where(user_hidden: false) unless viewer
          # If the viewer isn't spammy then we don't need to include the viewer_can_see query below since it
          # will never return anything.
          return where(user_hidden: false) if skip_user_filter_if_not_spammy && !viewer.spammy?

          viewer_can_see = if spammable_user_foreign_type.present? # Is a polymorphic association?
            where(user_association => viewer)
          else
            foreign_key ||= spammable_user_foreign_key
            where(foreign_key => viewer.id.to_s)
          end

          where(user_hidden: false).or(viewer_can_see)
        }

        # Records that are created by spammy users
        scope :spammy, lambda {
          where(user_hidden: true)
        }

        # Records that are not created by spammy users
        scope :not_spammy, lambda {
          return if !GitHub.spamminess_check_enabled?
          where(user_hidden: false)
        }

        define_method(:spammy?) do
          user_hidden?
        end

        define_method(:user_association_for_spammy) do
          user_association
        end

        # Checks if the viewer is not the author of this content
        define_method(:other_user_authored_content?) do |viewer|
          if self.class.spammable_user_foreign_type # is user_association polymorphic?
            viewer.id != read_attribute(self.class.spammable_user_foreign_key) ||
              viewer.class.name != read_attribute(self.class.spammable_user_foreign_type)
          else
            viewer.id != read_attribute(self.class.spammable_user_foreign_key)
          end
        end

        define_method(:async_hide_from_user?) do |viewer|
          return Promise.resolve(false) unless GitHub.spamminess_check_enabled?
          return Promise.resolve(false) unless spammy?
          return Promise.resolve(true) if !viewer
          return Promise.resolve(false) if viewer.site_admin?

          return Promise.resolve(other_user_authored_content?(viewer)) unless self.is_a?(Repository)

          async_owner.then do |owner|
            Promise.all([owner&.async_business]).then do
              # Don't hide organization-owned repositories from the org members
              if owner&.organization? && !owner.hide_from_user?(viewer)
                false
              else
                other_user_authored_content?(viewer)
              end
            end
          end
        end

        define_method(:hide_from_user?) do |viewer|
          async_hide_from_user?(viewer).sync
        end

        define_method(:set_user_hidden) do
          user = send(user_association)
          return unless user
          # we have to set the integer value so we don't update this unnecessarily
          # see https://github.com/github/github/pull/204652/files#r778329972
          self.user_hidden = user.content_hidden? ? 1 : 0
        end

        define_singleton_method(:spammable_user_foreign_key) do
          user_association = user_association.to_s
          reflections[user_association].foreign_key
        end

        define_singleton_method(:spammable_user_foreign_type) do
          user_association = user_association.to_s
          reflections[user_association].foreign_type
        end

        Spam::Spammable.add_class_including(self)
      end
    end

    # Enqueues a job that runs #check_for_spam on this record
    def enqueue_check_for_spam
      CheckForSpamJob.enqueue(self)
    end

    private def instrument_user_hidden_change
      return unless GitHub.spamminess_check_enabled?

      tags = [
        "model:#{self.class.name}",
        user_hidden? ? "state:hidden" : "state:visible",
      ]

      GitHub.dogstats.increment "spammable.user_hidden_changed", tags: tags
    end
  end
end
