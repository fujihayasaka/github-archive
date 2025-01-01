# typed: true
# frozen_string_literal: true

class SponsorshipNewsletter < ApplicationRecord::Domain::Sponsors
  extend GitHub::Encoding
  force_utf8_encoding :body, :subject

  include Instrumentation::Model
  include UrlHelpers
  include GitHub::Relay::GlobalIdentification

  belongs_to :sponsorable, class_name: "User", inverse_of: :sponsorship_newsletters
  belongs_to :sponsors_listing, foreign_key: :sponsorable_id, primary_key: :sponsorable_id,
    inverse_of: :newsletters
  # rubocop:todo Rails/InverseOf
  belongs_to :author, foreign_key: :author_id, class_name: "User"
  has_many :sponsorships, foreign_key: :sponsorable_id, primary_key: :sponsorable_id
  has_many :active_sponsorships, -> do
    T.bind(self, T.untyped)
    active
  end, foreign_key: :sponsorable_id, primary_key: :sponsorable_id, class_name: "Sponsorship"
  # rubocop:enable Rails/InverseOf
  has_many :sponsorship_newsletter_tiers, autosave: true, dependent: :destroy
  has_many :sponsors_tiers, through: :sponsorship_newsletter_tiers, dependent: :destroy

  validates :author_id, :sponsorable_id, :subject, :body, presence: true
  validate :published_newsletter_cannot_become_draft

  after_commit :after_publish, on: [:create, :update], if: -> do
    T.bind(self, SponsorshipNewsletter)
    saved_change_to_state? && published?
  end

  enum :state, {
    draft: 0,
    published: 1,
  }

  PER_PAGE = 10

  scope :for_sponsorable, ->(sponsorable_or_id) { where(sponsorable_id: sponsorable_or_id) }

  scope :sponsorship_matches_newsletter_tiers, -> do
    left_joins(:active_sponsorships)
      .left_joins(:sponsorship_newsletter_tiers)
      .where("sponsorship_newsletter_tiers.id IS NULL OR " \
             "sponsorship_newsletter_tiers.sponsors_tier_id = sponsorships.subscribable_id")
  end

  scope :with_approved_listing, -> do
    joins(:sponsors_listing).merge(SponsorsListing.with_approved_state)
  end

  # Public: Get all newsletters that are visible to the given user.
  #
  # viewer - a User or nil
  #
  # Returns an ActiveRecord::Relation of SponsorshipNewsletter.
  scope :visible_to, ->(viewer) do
    if viewer
      base_query = joins(:sponsors_listing).left_joins(:active_sponsorships).left_joins(:sponsorship_newsletter_tiers)
      viewer_and_owned_org_ids = [viewer.id] + viewer.owned_organization_ids

      # Newsletters visible to the viewer because the viewer is the admin of a Sponsors listing:
      newsletters_for_sponsorable = base_query.for_sponsorable(viewer_and_owned_org_ids)

      # Newsletters visible to the viewer because the viewer sponsors the maintainer:
      newsletters_for_sponsor = published
        .sponsorship_matches_newsletter_tiers
        .with_approved_listing
        .merge(Sponsorship.from_sponsor(viewer_and_owned_org_ids))

      # All newsletters visible to the viewer:
      newsletters_for_sponsorable.or(newsletters_for_sponsor).distinct
    else
      none
    end
  end

  # Public: Get text to let the recipient unsubscribe from sponsorship emails.
  #
  # sponsorable - the User or Organization who is being sponsored
  sig { params(sponsorable: GitHubSponsors::Types::Sponsorable).returns(String) }
  def self.unsubscribe_footer_for(sponsorable)
    unsubscribe_url = UrlHelpers.sponsorable_url(sponsorable, host: GitHub.host_name)
    <<~MARKDOWN

       ___

       Unsubscribe by unchecking "Receive email updates from #{sponsorable}" at <#{unsubscribe_url}>.
    MARKDOWN
  end

  # Public: Convert plain text or Markdown into HTML for display in update emails from a maintainer.
  #
  # text_body - a String of text or Markdown
  #
  # Returns a String of HTML.
  sig { params(text_body: String).returns(String) }
  def self.html_body_for(text_body)
    GitHub::Goomba::MarkdownPipeline.to_html(text_body)
  end

  sig { returns T.nilable(T::Boolean) }
  def for_organization?
    sponsorable&.organization?
  end

  sig { returns T.any(GitHubSponsors::Types::Sponsorable, Symbol) }
  def target_for_conditional_access
    async_target_for_conditional_access.sync
  end

  sig { returns Promise[T.any(GitHubSponsors::Types::Sponsorable, Symbol)] }
  def async_target_for_conditional_access
    async_sponsorable.then do |sponsorable|
      T.must(sponsorable).async_target_for_conditional_access
    end
  end

  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def readable_by?(actor)
    async_readable_by?(actor).sync
  end

  sig { params(actor: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_readable_by?(actor)
    return Promise.resolve(T.let(false, T::Boolean)) unless actor

    async_sponsors_listing_adminable_by?(actor).then do |is_listing_adminable|
      next true if is_listing_adminable

      # If the newsletter hasn't been published, no one besides the sponsorable can read it:
      next false if draft?

      async_sponsors_listing_readable_by?(actor).then do |is_listing_readable|
        # If the Sponsors listing isn't publicly available, it doesn't matter if the newsletter is published or not,
        # no one besides the sponsorable should see it:
        next false unless is_listing_readable

        async_sponsorable.then do |sponsorable|
          next false unless sponsorable

          async_sponsorship_newsletter_tiers.then do |sponsorship_newsletter_tiers|
            tier_ids = if sponsorship_newsletter_tiers.any?
              sponsorship_newsletter_tiers.map(&:sponsors_tier_id)
            end
            actor_and_owned_org_ids = [actor.id] + actor.owned_organization_ids

            # Allow the viewer to see a published newsletter when they're a sponsor, or when the viewer is an admin
            # of a sponsoring org:
            sponsorable.async_sponsor_exists_and_is_visible_to?(actor_and_owned_org_ids, viewer: actor,
              tier_ids: tier_ids)
          end
        end
      end
    end
  end

  # Public: The sponsors who have access to this newsletter. Includes those who are privately sponsoring.
  #
  # Returns an ActiveRecord::Relation of User.
  sig { returns ActiveRecord::Relation }
  def sponsors_with_access
    return User.none unless sponsorable
    sponsorships_scope = Sponsorship.emailable
    sponsorships_scope = sponsorships_scope.with_tier(sponsors_tier_ids) unless for_all_tiers?
    T.must(sponsorable).all_active_sponsors(sponsorships_scope: sponsorships_scope).order(:id)
  end

  # Public: Is this newsletter accessible to all tiers, instead of being restricted to certain tiers?
  sig { returns(T::Boolean) }
  def for_all_tiers?
    !sponsorship_newsletter_tiers.exists?
  end

  sig { returns User }
  def safe_author
    author || User.ghost
  end

  sig { params(viewer: T.nilable(User)).returns(Promise[T.nilable(User)]) }
  def async_author_for(viewer:)
    async_author.then do |user|
      user if user && !user.hide_from_user?(viewer)
    end
  end

  private

  sig { params(actor: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_sponsors_listing_adminable_by?(actor)
    async_sponsors_listing.then do |sponsors_listing|
      next false unless sponsors_listing
      sponsors_listing.async_adminable_by?(actor)
    end
  end

  sig { params(actor: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_sponsors_listing_readable_by?(actor)
    async_sponsors_listing.then do |sponsors_listing|
      next false unless sponsors_listing
      sponsors_listing.async_readable_by?(actor)
    end
  end

  sig { void }
  def published_newsletter_cannot_become_draft
    if state_was == "published" && state == "draft"
      errors.add(:state, "can't save draft after newsletter has been published")
    end
  end

  sig { void }
  def after_publish
    send_mailer
    instrument_events
  end

  sig { void }
  def send_mailer
    return unless GitHub.sponsors_enabled? && sponsorable

    body_with_footer = body + self.class.unsubscribe_footer_for(T.must(sponsorable))
    sponsors_with_access.each do |sponsor|
      SponsorsMailer.one_click_unsubscribe_newsletter(
        sponsorable: T.must(sponsorable),
        sponsor: sponsor,
        subject: self.subject,
        text_body: body_with_footer,
        html_body: self.class.html_body_for(body_with_footer),
      ).deliver_later
    end
  end

  sig { returns Symbol }
  def event_prefix() :sponsorship_newsletter end

  sig { returns T::Hash[T.any(String, Symbol), T.untyped] }
  def event_payload
    payload = { event_prefix => self }
    payload.merge!(T.must(sponsorable).event_context) if sponsorable
    payload
  end

  sig { void }
  def instrument_events
    # Audit log
    instrument :sponsored_developer_update_newsletter_send, prefix: :sponsors

    # Hydro
    GlobalInstrumenter.instrument("sponsors.sponsored_developer_update_newsletter_send",
      sponsored_developer: sponsorable,
      subject: self.subject,
      body: self.body
    )
  end
end
