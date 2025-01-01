# typed: true
# frozen_string_literal: true

class AuthorAssociationBase
  def initialize(resource:, user:)
    @resource = resource
    @user = user
  end

  # Note: string is returned in all caps to ensure the REST API remains
  # consistent with app/platform/enums/comment_author_association.rb
  def to_s
    to_sym.to_s.upcase
  end

  def to_sym
    async_to_sym.sync
  end

  def async_contributor_pull_request_count(repository:, user_id:)
    Platform::Loaders::ContributorOpenPullRequestCount.load(repository, user_id)
  end

  def async_pull_request_count(user)
    Platform::Loaders::PullRequestCount.load(user)
  end

  # Override these in the subclass if you need to
  def async_mannequin?; false; end
  def async_owner?; false; end
  def async_member?; false; end
  def async_collaborator?; false; end
  def async_contributor?; false; end
  def async_first_timer?; false; end
  def async_first_time_contributor?; false; end

  def async_to_sym
    badge_checks = [
      async_mannequin?,
      async_owner?,
      async_member?,
      async_collaborator?,
      async_contributor?,
      async_first_timer?,
      async_first_time_contributor?,
    ]

    Promise.all(badge_checks).then do |is_mannequin, is_owner, is_member, is_collaborator, is_contributor, is_first_timer, is_first_time_contributor|
      if is_mannequin
        :mannequin
      elsif is_owner
        :owner
      elsif is_member
        :member
      elsif is_collaborator
        :collaborator
      elsif is_contributor
        :contributor
      elsif is_first_timer
        :first_timer
      elsif is_first_time_contributor
        :first_time_contributor
      else
        :none
      end
    end
  end

  def async_to_sym_candidate
    # Don't use `Promise.all` here because we want to return the first truthy value
    # And save redundant checks
    async_owner?.then do |is_owner|
      next :owner if is_owner

      async_member?.then do |is_member|
        next :member if is_member

        async_mannequin?.then do |is_mannequin|
          next :mannequin if is_mannequin

          async_collaborator?.then do |is_collaborator|
            next :collaborator if is_collaborator

            async_contributor?.then do |is_contributor|
              next :contributor if is_contributor

              async_first_timer?.then do |is_first_timer|
                next :first_timer if is_first_timer

                async_first_time_contributor?.then do |is_first_time_contributor|
                  next :first_time_contributor if is_first_time_contributor

                  :none
                end
              end
            end
          end
        end
      end
    end
  end

  private

  attr_reader :resource
  attr_reader :user
end
