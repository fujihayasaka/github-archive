# typed: true
# frozen_string_literal: true

module OrganizationDiscussionItem
  extend ActiveSupport::Concern
  extend T::Helpers

  include GitHub::Relay::GlobalIdentification
  include GitHub::UserContent
  include UserContentEditable

  abstract!

  requires_ancestor { ActiveRecord::Base }

  sig { abstract.params(actor: T.untyped).returns(Promise[T::Boolean]) }
  def async_is_programmatic_actor_with_write_access?(actor); end

  sig { abstract.params(actor: T.untyped).returns(Promise[T::Boolean]) }
  def async_readable_by?(actor); end

  sig { abstract.returns(Promise[T.nilable(Organization)]) }
  def async_organization; end

  sig { abstract.returns(String) }
  def body; end

  sig { abstract.returns(Integer) }
  def user_id; end

  included do
    T.bind(self, T.class_of(ActiveRecord::Base))

    attribute :body, StringFromBinary.new

    validate :body_is_present
  end

  sig { params(viewer: T.untyped).returns(T::Boolean) }
  def viewer_can_update?(viewer)
    async_viewer_can_update?(viewer).sync
  end

  sig { params(viewer: T.untyped).returns(Promise[T::Boolean]) }
  def async_viewer_can_update?(viewer)
    async_viewer_cannot_update_reasons(viewer).then(&:empty?)
  end

  sig { params(viewer: T.untyped).returns(Promise[T::Array[Symbol]]) }
  def async_viewer_cannot_update_reasons(viewer)
    return Promise.resolve(T.let([:login_required], T::Array[Symbol])) unless viewer

    async_programmatic_actor_reasons = if viewer.can_have_granular_permissions?
      async_is_programmatic_actor_with_write_access?(viewer).then do |has_access|
        has_access ? [] : [:insufficient_access]
      end
    else
      Promise.resolve([])
    end

    async_user_reasons = async_readable_by?(viewer).then do |readable|
      next [:insufficient_access] unless readable
      next [] if viewer.id == user_id

      async_organization.then do |org|
        org_adminable_promise = org ? org.async_adminable_by?(viewer) : Promise.resolve(false)
        org_adminable_promise.then do |is_adminable|
          is_adminable ? [] : [:insufficient_access]
        end
      end
    end

    all_promises = Promise.all([async_programmatic_actor_reasons, async_user_reasons])
    all_promises.then do |programmatic_actor_reasons, user_reasons|
      (programmatic_actor_reasons + user_reasons).uniq
    end
  end

  # Public: Can the given viewer delete this org discussion?
  sig do
    params(
      viewer: T.nilable(T.any(IntegrationInstallation, Bot, ProgrammaticAccessBot, User))
    ).returns(Promise[T::Boolean])
  end
  def async_viewer_can_delete?(viewer)
    return Promise.resolve(T.let(false, T::Boolean)) unless viewer

    async_programmatic_actor_can_delete = if viewer.can_have_granular_permissions?
      async_is_programmatic_actor_with_write_access?(viewer)
    else
      Promise.resolve(true)
    end

    async_user_can_delete = async_readable_by?(viewer).then do |readable|
      next false unless readable
      next true if viewer.id == user_id

      async_organization.then { |org| org ? org.async_adminable_by?(viewer) : false }
    end

    Promise.all([async_programmatic_actor_can_delete, async_user_can_delete]).then(&:all?)
  end

  sig do
    params(
      viewer: T.nilable(T.any(IntegrationInstallation, Bot, ProgrammaticAccessBot, User))
    ).returns(T::Boolean)
  end
  def viewer_can_delete?(viewer)
    async_viewer_can_delete?(viewer).sync
  end

  private

  sig { void }
  def body_is_present
    errors.add(:body, "cannot be blank") if self[:body]&.strip.blank?
  end
end
